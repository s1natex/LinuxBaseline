# This a Ubuntu 22.04 vm configuration for DevOps uses
This Repo is created to have a consistent vm for DevOps Practices
## Instructions:
- Prerequisites:
    - Vagrant 2.4.3
    - VirtualBox 7.1.6
```
# cd into repo path and Boot the vm
vagrant up
# Wait for Boot to complete and show all tests passed
vagrant ssh
```
## boot.sh installs and configures:
- **Base utilities**: `git`, `vim`, `nano`, `jq`, `tree`, `htop`, `tmux`, `ripgrep`, `fzf`
- **Networking tools**: `net-tools`, `iproute2`, `dnsutils`, `nmap`, `tcpdump`, `ping`
- **Security**: `ufw`, `fail2ban` (enabled at boot)
- **Languages & runtimes**: `python3`, `pip3`, `openjdk-11-jdk`, `nodejs`, `npm`
- **Containers & DevOps**: `docker.io`, `docker-compose`, `terraform`, `ansible`
- **System-wide Vim config**: `/etc/vim/vimrc.local` with line numbers, syntax highlighting, indentation, and quality-of-life settings
---
