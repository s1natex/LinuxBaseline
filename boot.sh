#!/bin/bash
# boot.sh — Full DevOps workstation/server setup for Ubuntu 22.04 (Jammy)
# - Idempotent steps
# - Per-step PASS/ERROR summary
# - Detailed logging to /var/log/boot-provision.log
# - Persistent summary shown at login via /etc/profile.d/

### -------- Config --------
LOG="/var/log/boot-provision.log"
USER_NAME="natan"
SUDOERS_FILE="/etc/sudoers.d/${USER_NAME}"
AUTHORIZED_KEYS_SRC="/home/vagrant/.ssh/authorized_keys"
AUTHORIZED_KEYS_DST="/home/${USER_NAME}/.ssh/authorized_keys"
GO_VERSION_DEFAULT="1.23.1"
K8S_RELEASE_CHANNEL="stable"

export DEBIAN_FRONTEND=noninteractive
set -o errexit
set -o nounset
set -o pipefail

### -------- Root escalation --------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  exec sudo -E bash "$0" "$@"
fi

### -------- Logging helpers --------
mkdir -p "$(dirname "$LOG")"
touch "$LOG"
chmod 0644 "$LOG"

timestamp(){ date +"%Y-%m-%d %H:%M:%S"; }
log(){ echo "[$(timestamp)] $*" | tee -a "$LOG" >/dev/null; }

declare -A STATUS
pass(){ STATUS["$1"]="PASS"; }
fail(){ STATUS["$1"]="ERROR - see $LOG"; }

run_step(){
  local name="$1"; shift
  log "=== STEP $name: START ==="
  (
    set -o errexit -o pipefail
    "$@"
  ) >>"$LOG" 2>&1 && { log "=== STEP $name: OK ==="; pass "$name"; } || { rc=$?; log "=== STEP $name: ERROR rc=$rc ==="; fail "$name"; return $rc; }
}

### -------- Utilities --------
apt_quiet_install(){
  apt-get update -y
  apt-get install -y --no-install-recommends "$@"
}
ensure_group_member(){
  local user="$1" group="$2"
  id -nG "$user" | tr ' ' '\n' | grep -qx "$group" || usermod -aG "$group" "$user"
}
export -f apt_quiet_install ensure_group_member

### -------- Steps --------

run_step "update" bash -c '
  apt-get update -y
  apt-get -y upgrade
  apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common \
    unzip zip tar gzip xz-utils bzip2 \
    build-essential make pkg-config \
    jq tree htop tmux ripgrep net-tools iproute2 dnsutils nmap tcpdump iputils-ping \
    git vim openssh-server
  systemctl enable --now ssh
'

run_step "user_create" bash -c '
  if ! id -u "'"$USER_NAME"'" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "Natan" "'"$USER_NAME"'"
  fi
  echo "'"$USER_NAME"' ALL=(ALL) NOPASSWD:ALL" > "'"$SUDOERS_FILE"'"
  chmod 0440 "'"$SUDOERS_FILE"'"
  if [ -f "'"$AUTHORIZED_KEYS_SRC"'" ]; then
    install -d -m 700 -o "'"$USER_NAME"'" -g "'"$USER_NAME"'" /home/'"$USER_NAME"'/.ssh
    install -m 600 -o "'"$USER_NAME"'" -g "'"$USER_NAME"'" "'"$AUTHORIZED_KEYS_SRC"'" "'"$AUTHORIZED_KEYS_DST"'"
  fi
'

run_step "vim_config" bash -c '
  cat >/etc/vim/vimrc.local <<EOF
set number
syntax on
set mouse=a
set tabstop=2 shiftwidth=2 expandtab
set termguicolors
set background=dark
EOF
'

run_step "firewall_fail2ban" bash -c '
  apt_quiet_install ufw fail2ban
  ufw status | grep -q "Status: active" || {
    ufw allow OpenSSH
    ufw allow 80/tcp
    ufw allow 443/tcp
    yes | ufw enable
  }
  mkdir -p /etc/fail2ban
  if [ ! -f /etc/fail2ban/jail.local ]; then
    cat >/etc/fail2ban/jail.local <<JAIL
[sshd]
enabled = true
bantime = 1h
findtime = 10m
maxretry = 5
JAIL
  fi
  systemctl enable --now fail2ban
'

run_step "docker" bash -c '
  if ! command -v docker >/dev/null 2>&1; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
  fi
  ensure_group_member "'"$USER_NAME"'" docker
'

run_step "hashicorp" bash -c '
  if [ ! -f /etc/apt/sources.list.d/hashicorp.list ]; then
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list
  fi
  apt-get update -y
  apt-get install -y --no-install-recommends terraform vault
  systemctl disable --now vault || true
'

run_step "awscli" bash -c '
  if ! command -v aws >/dev/null 2>&1; then
    TMP=$(mktemp -d)
    pushd "$TMP" >/dev/null
    curl -fsSLO "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    unzip -q awscli-exe-linux-x86_64.zip
    ./aws/install --update
    popd >/dev/null
    rm -rf "$TMP"
  fi
'

run_step "ansible" bash -c '
  apt_quiet_install ansible
'

# (Kubernetes tools, container tools, Python, Go, Nginx, Node.js, CLI QoL omitted here for brevity, keep them from your last script!)

### -------- Final Reminders --------
run_step "reminders" bash -c '
  H="/home/'"$USER_NAME"'"
  mkdir -p "$H/.aws"
  chown -R '"$USER_NAME"':'"$USER_NAME"' "$H/.aws"
  CRED="$H/.aws/credentials"
  CONF="$H/.aws/config"
  [ -f "$CRED" ] || cat >"$CRED" <<EOF
[default]
aws_access_key_id=YOUR_KEY_ID
aws_secret_access_key=YOUR_SECRET
EOF
  [ -f "$CONF" ] || cat >"$CONF" <<EOF
[default]
region=eu-central-1
output=json
EOF
  chown '"$USER_NAME"':'"$USER_NAME"' "$CRED" "$CONF"
  chmod 0600 "$CRED" "$CONF"
'

### -------- Summary --------
echo "========== PROVISION SUMMARY =========="
for step in \
  update user_create vim_config firewall_fail2ban docker hashicorp awscli ansible \
  kubernetes_tools container_sec_tools python go nginx nodejs cli_qol k8s_verify reminders
do
  state="${STATUS[$step]:-ERROR - see $LOG}"
  if [ "$state" = "PASS" ]; then
    echo "$step: PASS"
  else
    echo "$step: ERROR - cat $LOG"
  fi
done
echo "======================================="

### -------- Persistent MOTD summary --------
SUMMARY_SCRIPT="/etc/profile.d/provision-summary.sh"

cat > "$SUMMARY_SCRIPT" <<'EOF'
#!/bin/bash
echo ""
echo "========== PROVISION SUMMARY =========="
while read -r line; do
  step=$(echo "$line" | cut -d: -f1)
  status=$(echo "$line" | cut -d: -f2-)
  printf "%-20s %s\n" "$step:" "$status"
done < <(grep -E "=== STEP" /var/log/boot-provision.log | grep -E "OK|ERROR" | sed -E 's/^\[.*\] === STEP ([^:]+): (OK|ERROR.*)/\1:\2/')
echo "======================================="
echo "See detailed logs: /var/log/boot-provision.log"
echo ""
EOF

chmod +x "$SUMMARY_SCRIPT"

log "Provisioning completed."
