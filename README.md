# LinuxBaseline
A multi distro configuration bash script
## Installation
- Install Git
- Run install.sh
```
git clone https://github.com/s1natex/LinuxBaseline
chmod +x install.sh
./install.sh
```
## What it does
- Creates a sudoer user with a home dir
- Updates system and installs linux tools:
```
curl, wget, git, unzip, make, gcc
zsh, tmux, ripgrep, fzf, bat, exa
htop, btop, glances, nmap, iftop
dnsutils, whois, tcpdump, iproute2
```
- Installs additional tools:
```
python3, pip, venv
docker, docker-compose #Adds Docker group access(needs login)
Ansible, Terraform, Kubernetes and kubectl
Jenkins with Java 17
Prometheus and Creates prometheus system user #Prepares config and data directories
Installs and enables fail2ban
Disables root SSH login
Installs neovim
Sets up amix/vimrc for user Natan
Adds weekly system cleanup cron job:
    - apt/dnf autoremove
    - docker system prune
Creates /home/Natan/.help.txt
```