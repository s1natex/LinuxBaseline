#!/bin/bash
set -e

check_cmd() {
  local name=$1
  local cmd=$2

  if command -v $cmd >/dev/null 2>&1; then
    printf "%-20s: Pass\n" "$name"
  else
    printf "%-20s: Fail\n" "$name"
  fi
}

check_service() {
  local name=$1
  local svc=$2

  if systemctl is-active --quiet $svc; then
    printf "%-20s: Pass\n" "$name"
  else
    printf "%-20s: Fail\n" "$name"
  fi
}

echo "===== Boot Check ====="

# Base utilities
check_cmd "git" git
check_cmd "vim" vim
check_cmd "jq" jq
check_cmd "tree" tree
check_cmd "htop" htop
check_cmd "tmux" tmux
check_cmd "ripgrep" rg
check_cmd "fzf" fzf
check_cmd "nmap" nmap
check_cmd "tcpdump" tcpdump
check_cmd "ping" ping

# Networking & security
check_cmd "ufw" ufw
check_service "ufw service" ufw
check_cmd "fail2ban" fail2ban-server
check_service "fail2ban service" fail2ban

# Languages & runtimes
check_cmd "python3" python3
check_cmd "pip3" pip3
check_cmd "Java (OpenJDK11)" java
check_cmd "nodejs" node
check_cmd "npm" npm

# Containers & DevOps
check_cmd "docker" docker
check_service "docker service" docker
check_cmd "docker-compose" docker-compose
check_cmd "terraform" terraform
check_cmd "ansible" ansible

# Vim config
if grep -q "syntax on" ~/.vimrc && grep -q "set number" ~/.vimrc; then
  printf "%-20s: Pass\n" "Vim config"
else
  printf "%-20s: Fail\n" "Vim config"
fi

echo "===== Check Complete ====="
