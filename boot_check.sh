#!/bin/bash
set -e

fail_count=0

p() { # print aligned Pass/Fail and count failures
  local name="$1" ok="$2"
  if [ "$ok" = "0" ]; then
    printf "%-20s: Pass\n" "$name"
  else
    printf "%-20s: Fail\n" "$name"
    fail_count=$((fail_count+1))
  fi
}

check_cmd() {
  local name="$1" cmd="$2"
  command -v "$cmd" >/dev/null 2>&1
  p "$name" $?
}

check_service() {
  local name="$1" svc="$2"
  systemctl is-active --quiet "$svc"
  p "$name" $?
}

# ---------- Base utilities ----------
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

# ---------- Networking & security ----------
check_cmd "ufw" ufw
check_service "ufw service" ufw
check_cmd "fail2ban" fail2ban-server
check_service "fail2ban service" fail2ban

# ---------- Languages & runtimes ----------
check_cmd "python3" python3
check_cmd "pip3" pip3
check_cmd "Java (OpenJDK11)" java
check_cmd "nodejs" node
check_cmd "npm" npm

# ---------- Containers & DevOps ----------
check_cmd "docker" docker
check_service "docker service" docker
check_cmd "docker-compose" docker-compose
check_cmd "terraform" terraform
check_cmd "ansible" ansible

# ---------- Vim config check (user or system-wide) ----------
vim_cfg_status=1

# 1) If user has ~/.vimrc with key lines, accept
if [ -f "$HOME/.vimrc" ] && grep -q "syntax on" "$HOME/.vimrc" && grep -q "set number" "$HOME/.vimrc"; then
  vim_cfg_status=0
else
  # 2) Else, accept system-wide /etc/vim/vimrc.local if it has key lines
  if [ -f /etc/vim/vimrc.local ] && grep -q "syntax on" /etc/vim/vimrc.local && grep -q "set number" /etc/vim/vimrc.local; then
    vim_cfg_status=0
  fi
fi

# 3) Optional: verify Vim is actually sourcing one of them
# (doesn't change Pass/Fail if above already passed, but tightens the check if desired)
if [ $vim_cfg_status -eq 0 ] && command -v vim >/dev/null 2>&1; then
  # capture where 'number' was last set from
  src_out="$(vim +'verbose set number?' +q 2>&1 || true)"
  if ! echo "$src_out" | grep -Eq 'Last set from .*vimrc(\.local)?'; then
    # if Vim didn't report, keep it Pass based on files existing, but you can uncomment next line to force Fail:
    # vim_cfg_status=1
    :
  fi
fi

p "Vim config" $((vim_cfg_status!=0))

# ---------- Exit code ----------
# Non-zero exit if any check failed (useful for CI or automation)
exit $fail_count
