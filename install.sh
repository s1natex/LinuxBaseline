#!/bin/bash
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo bash install.sh)"
  exit 1
fi

if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO=$ID
else
  echo "Unsupported OS"
  exit 1
fi

install_common_packages_debian() {
  apt update && apt upgrade -y
  apt install -y \
    curl wget git unzip build-essential software-properties-common \
    zsh tmux fzf ripgrep bat exa \
    python3 python3-pip python3-venv \
    docker.io docker-compose \
    ansible \
    ufw fail2ban \
    jq yq \
    gnupg lsb-release ca-certificates \
    net-tools htop btop iftop nmap \
    iperf3 dnsutils whois tcpdump \
    neovim openjdk-17-jdk
}

install_common_packages_rhel() {
  dnf install -y epel-release
  dnf install -y \
    curl wget git unzip make gcc zsh tmux \
    python3 python3-pip python3-virtualenv \
    docker docker-compose \
    ansible \
    firewalld fail2ban \
    jq \
    glances htop iftop nmap \
    ripgrep fzf bat exa \
    java-17-openjdk \
    iperf bind-utils whois tcpdump \
    neovim
}

install_common_packages_arch() {
  pacman -Sy --noconfirm \
    curl wget git unzip base-devel zsh tmux \
    python python-pip \
    docker docker-compose \
    ansible \
    ufw fail2ban \
    jq \
    glances htop iftop nmap \
    ripgrep fzf bat exa \
    jdk-openjdk \
    iperf dnsutils whois tcpdump \
    neovim
}

setup_terraform() {
  if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list
    apt update && apt install -y terraform
  elif [[ "$DISTRO" == "rhel" || "$DISTRO" == "centos" || "$DISTRO" == "rocky" ]]; then
    dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
    dnf install -y terraform
  elif [[ "$DISTRO" == "arch" ]]; then
    pacman -Sy --noconfirm terraform
  fi
}

setup_jenkins() {
  if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
    curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key | gpg --dearmor -o /usr/share/keyrings/jenkins.gpg
    echo deb [signed-by=/usr/share/keyrings/jenkins.gpg] https://pkg.jenkins.io/debian binary/ > /etc/apt/sources.list.d/jenkins.list
    apt update && apt install -y jenkins
  elif [[ "$DISTRO" == "rhel" || "$DISTRO" == "centos" || "$DISTRO" == "rocky" ]]; then
    dnf install -y java-17-openjdk
    curl -o /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key
    dnf install -y jenkins
  fi
}

setup_kubectl() {
  curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
}

setup_prometheus_user() {
  useradd --no-create-home --shell /bin/false prometheus || true
  mkdir -p /etc/prometheus /var/lib/prometheus
  chown prometheus:prometheus /etc/prometheus /var/lib/prometheus
}

create_user_natan() {
  useradd -m -s /bin/bash Natan || true
  usermod -aG sudo Natan || usermod -aG wheel Natan || true
  echo "Natan ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/Natan
}

setup_vim_for_natan() {
  sudo -u Natan bash -c "
    git clone --depth=1 https://github.com/amix/vimrc.git /home/Natan/.vim_runtime
    sh /home/Natan/.vim_runtime/install_awesome_vimrc.sh
  "
}

harden_ssh_and_fail2ban() {
  sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
  systemctl restart sshd || service sshd restart
  systemctl enable fail2ban
  systemctl start fail2ban
}

setup_cleanup_cron() {
  mkdir -p /etc/cron.weekly
  cat << 'EOF' > /etc/cron.weekly/system-cleanup
#!/bin/bash
apt autoremove -y 2>/dev/null
apt clean 2>/dev/null
dnf autoremove -y 2>/dev/null
dnf clean all 2>/dev/null
docker system prune -af 2>/dev/null
EOF
  chmod +x /etc/cron.weekly/system-cleanup
}

create_help_file() {
  cat << 'EOF' > /home/Natan/.help.txt
[JENKINS]
sudo cat /var/lib/jenkins/secrets/initialAdminPassword

[DOCKER]
sudo systemctl start docker
sudo usermod -aG docker $USER

[TERRAFORM]
terraform init
terraform validate
terraform plan

[KUBECTL]
kubectl config view
kubectl get nodes
kubectl get pods -A

[SYSTEM]
htop
ufw status
fail2ban-client status

[PYTHON VENV]
python3 -m venv .venv
source .venv/bin/activate

[GIT]
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
EOF

  chown Natan:Natan /home/Natan/.help.txt
}

create_user_natan

case "$DISTRO" in
  ubuntu|debian)
    install_common_packages_debian
    ;;
  rhel|centos|rocky|almalinux|fedora)
    install_common_packages_rhel
    ;;
  arch|manjaro)
    install_common_packages_arch
    ;;
  *)
    echo "Unsupported distro: $DISTRO"
    exit 1
    ;;
esac

setup_terraform
setup_jenkins
setup_kubectl
setup_prometheus_user
setup_vim_for_natan
harden_ssh_and_fail2ban
setup_cleanup_cron
create_help_file

echo "Setup complete... Switch to user 'Natan' and check ~/.help.txt"
