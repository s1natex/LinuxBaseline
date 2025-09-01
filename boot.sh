#!/bin/bash
# boot.sh — Full DevOps workstation/server setup for Ubuntu 22.04 (Jammy)
# - Idempotent steps
# - Per-step PASS/ERROR summary
# - Detailed logging to /var/log/boot-provision.log

### -------- Config --------
LOG="/var/log/boot-provision.log"
USER_NAME="Natan"
SUDOERS_FILE="/etc/sudoers.d/${USER_NAME}"
AUTHORIZED_KEYS_SRC="/home/vagrant/.ssh/authorized_keys"
AUTHORIZED_KEYS_DST="/home/${USER_NAME}/.ssh/authorized_keys"
GO_VERSION_DEFAULT="1.23.1"   # change if you want to pin a different version
K8S_RELEASE_CHANNEL="stable"  # kubectl apt repo channel

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
  # safe apt install wrapper
  apt-get update -y
  apt-get install -y --no-install-recommends "$@"
}

ensure_group_member(){
  local user="$1" group="$2"
  id -nG "$user" | tr ' ' '\n' | grep -qx "$group" || usermod -aG "$group" "$user"
}

write_file(){
  local path="$1"; shift
  install -D -m 0644 /dev/stdin "$path" <<<"$*"
}

### -------- Steps --------

# 0) Base system update + essentials
run_step "update" bash -c '
  apt-get update -y
  apt-get -y upgrade
  apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common \
    unzip zip tar gzip xz-utils bzip2 \
    build-essential make pkg-config \
    jq yq tree htop tmux ripgrep net-tools iproute2 dnsutils nmap tcpdump iputils-ping \
    git vim openssh-server
  systemctl enable --now ssh
'

# 1) Create user Natan with sudo + copy vagrant authorized_keys
run_step "user_create" bash -c '
  if ! id -u "'"$USER_NAME"'" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "'"$USER_NAME"'"
  fi
  echo "'"$USER_NAME"' ALL=(ALL) NOPASSWD:ALL" > "'"$SUDOERS_FILE"'"
  chmod 0440 "'"$SUDOERS_FILE"'"
  if [ -f "'"$AUTHORIZED_KEYS_SRC"'" ]; then
    install -d -m 700 -o "'"$USER_NAME"'" -g "'"$USER_NAME"'" /home/'"$USER_NAME"'/.ssh
    install -m 600 -o "'"$USER_NAME"'" -g "'"$USER_NAME"'" "'"$AUTHORIZED_KEYS_SRC"'" "'"$AUTHORIZED_KEYS_DST"'"
  fi
'

# 2) Configure vim (line numbers + syntax + sensible defaults)
run_step "vim_config" bash -c '
  write_vim() {
    cat <<EOF
set number
syntax on
set mouse=a
set tabstop=2 shiftwidth=2 expandtab
set termguicolors
set background=dark
EOF
  }
  write_vim | tee /etc/vim/vimrc.local >/dev/null
'

# 3) UFW + fail2ban (allow SSH/HTTP/HTTPS; enable sshd jail)
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

# 4) Docker Engine + Compose v2 (official repo) and add user to docker group
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

# 5) HashiCorp repo: Terraform + Vault (+ optional Packer commented)
run_step "hashicorp" bash -c '
  if [ ! -f /etc/apt/sources.list.d/hashicorp.list ]; then
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list
  fi
  apt-get update -y
  apt-get install -y --no-install-recommends terraform vault
  systemctl disable --now vault || true
  # apt-get install -y packer   # uncomment if you want Packer too
'

# 6) AWS CLI v2
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

# 7) Ansible
run_step "ansible" bash -c '
  apt_quiet_install ansible
'

# 8) Kubernetes: kubectl (apt), minikube (deb), plus helpers (helm, kustomize, kubectx/kubens, k9s, stern)
run_step "kubernetes_tools" bash -c '
  # kubectl apt repo
  curl -fsSL https://pkgs.k8s.io/core:/kubernetes:/'"$K8S_RELEASE_CHANNEL"':/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/kubernetes:/'"$K8S_RELEASE_CHANNEL"':/v1.31/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
  apt-get update -y
  apt-get install -y --no-install-recommends kubectl

  # minikube
  if ! command -v minikube >/dev/null 2>&1; then
    curl -fsSLo /tmp/minikube.deb https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
    dpkg -i /tmp/minikube.deb || apt-get -f install -y
    rm -f /tmp/minikube.deb
  fi

  # helm
  if ! command -v helm >/dev/null 2>&1; then
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi

  # kustomize
  if ! command -v kustomize >/dev/null 2>&1; then
    KURL=$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest | jq -r ".assets[] | select(.name|test(\"linux_amd64.tar.gz$\")) | .browser_download_url")
    curl -fsSL "$KURL" | tar -xz -C /usr/local/bin
    chmod +x /usr/local/bin/kustomize
  fi

  # kubectx/kubens
  if ! command -v kubectx >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends kubectx
  fi

  # k9s
  if ! command -v k9s >/dev/null 2>&1; then
    K9S_URL=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | jq -r ".assets[] | select(.name|test(\"Linux_amd64.tar.gz$\")) | .browser_download_url")
    TMP=$(mktemp -d); pushd "$TMP" >/dev/null
    curl -fsSL "$K9S_URL" -o k9s.tgz
    tar -xzf k9s.tgz
    install -m 0755 k9s /usr/local/bin/k9s
    popd >/dev/null; rm -rf "$TMP"
  fi

  # stern
  if ! command -v stern >/dev/null 2>&1; then
    STERN_URL=$(curl -fsSL https://api.github.com/repos/stern/stern/releases/latest | jq -r ".assets[] | select(.name|test(\"linux_amd64.tar.gz$\")) | .browser_download_url")
    TMP=$(mktemp -d); pushd "$TMP" >/dev/null
    curl -fsSL "$STERN_URL" -o stern.tgz
    tar -xzf stern.tgz
    install -m 0755 stern_/stern /usr/local/bin/stern || install -m 0755 stern /usr/local/bin/stern
    popd >/dev/null; rm -rf "$TMP"
  fi
'

# 9) Container/security tools: trivy, cosign, dive, skopeo
run_step "container_sec_tools" bash -c '
  # trivy (Aqua Security apt)
  if ! command -v trivy >/dev/null 2>&1; then
    curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /usr/share/keyrings/trivy.gpg
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb stable main" > /etc/apt/sources.list.d/trivy.list
    apt-get update -y && apt-get install -y trivy
  fi

  # cosign
  if ! command -v cosign >/dev/null 2>&1; then
    COSIGN_URL=$(curl -fsSL https://api.github.com/repos/sigstore/cosign/releases/latest | jq -r ".assets[] | select(.name==\"cosign-linux-amd64\") | .browser_download_url")
    curl -fsSL "$COSIGN_URL" -o /usr/local/bin/cosign
    chmod +x /usr/local/bin/cosign
  fi

  # dive
  if ! command -v dive >/dev/null 2>&1; then
    DIVE_URL=$(curl -fsSL https://api.github.com/repos/wagoodman/dive/releases/latest | jq -r ".assets[] | select(.name|test(\"linux_amd64.deb$\")) | .browser_download_url")
    curl -fsSL "$DIVE_URL" -o /tmp/dive.deb
    dpkg -i /tmp/dive.deb || apt-get -f install -y
    rm -f /tmp/dive.deb
  fi

  # skopeo
  apt_quiet_install skopeo
'

# 10) Python (3.x + pip + venv + pipx)
run_step "python" bash -c '
  apt_quiet_install python3 python3-pip python3-venv python3-distutils
  if ! command -v pipx >/dev/null 2>&1; then
    python3 -m pip install -U pip setuptools wheel
    python3 -m pip install -U pipx
    python3 -m pipx ensurepath || true
  fi
'

# 11) Go (tarball to /usr/local/go, with profile.d export)
run_step "go" bash -c '
  GO_VER="'"$GO_VERSION_DEFAULT"'"
  if [ -d /usr/local/go ]; then
    INSTALLED=$(/usr/local/go/bin/go version | awk "{print \$3}" || true)
  else
    INSTALLED=""
  fi
  if [ "$INSTALLED" != "go$GO_VER" ]; then
    rm -rf /usr/local/go
    curl -fsSLo /tmp/go.tgz "https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz"
    tar -C /usr/local -xzf /tmp/go.tgz
    rm -f /tmp/go.tgz
  fi
  cat >/etc/profile.d/go.sh <<'EOS'
export PATH=/usr/local/go/bin:$PATH
export GOPATH=${HOME}/go
export PATH=${GOPATH}/bin:$PATH
EOS
  chmod 0644 /etc/profile.d/go.sh
'

# 12) NGINX
run_step "nginx" bash -c '
  apt_quiet_install nginx
  systemctl enable --now nginx
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
'

# 13) Node.js (LTS) - optional but helpful for tooling
run_step "nodejs" bash -c '
  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs
  fi
'

# 14) direnv + fzf + bat (quality of life)
run_step "cli_qol" bash -c '
  apt_quiet_install direnv fzf bat
  for shrc in /etc/bash.bashrc; do
    grep -q "direnv hook bash" "$shrc" || echo "eval \"\$(direnv hook bash)\"" >> "$shrc"
  done
'

# 15) kubectl/minikube quick sanity (do not start cluster, just version)
run_step "k8s_verify" bash -c '
  kubectl version --client --output=yaml >/dev/null
  minikube version >/dev/null
  helm version --short >/dev/null
'

### -------- Final Reminders / Info --------
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

  echo
  echo "AWS credentials placeholders written for user '"$USER_NAME"'."
  echo "Edit: $CRED and $CONF"
  echo
  echo "Minikube tip: run as $USER_NAME →  'newgrp docker && minikube start --driver=docker'"
  echo
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

# End of script
log "Provisioning completed."