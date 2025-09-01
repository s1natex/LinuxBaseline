#!/bin/bash
set -e

echo "Starting boot sequence..."
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export APT_LISTCHANGES_FRONTEND=none

# =========================
# Preseed common configs
# =========================
# Timezone
sudo ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime
echo "tzdata tzdata/Areas select Etc" | sudo debconf-set-selections
echo "tzdata tzdata/Zones/Etc select UTC" | sudo debconf-set-selections

# Locale
echo "locales locales/default_environment_locale select en_US.UTF-8" | sudo debconf-set-selections
sudo locale-gen en_US.UTF-8

# Suppress GRUB prompts
echo "grub-pc grub-pc/install_devices_empty boolean true"  | sudo debconf-set-selections
echo "grub-pc grub-pc/install_devices_failed boolean true" | sudo debconf-set-selections
echo "grub-pc grub-pc/hidden_timeout boolean true"         | sudo debconf-set-selections
echo "grub-pc grub-pc/timeout string 0"                    | sudo debconf-set-selections

# =========================
# Update & Upgrade
# =========================
# Prevent interactive kernel/service restart prompts
sudo apt-get -y purge needrestart update-notifier-common || true

sudo apt update -y

# Fully non-interactive upgrade (handles kernel + config prompts)
sudo NEEDRESTART_MODE=a apt-get \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold" \
  dist-upgrade -yq

# =========================
# Base Utilities
# =========================
sudo apt install -yq \
  build-essential pkg-config ca-certificates \
  curl wget gnupg lsb-release apt-transport-https \
  software-properties-common unzip zip tar gzip xz-utils bzip2 \
  git vim nano jq tree htop tmux ripgrep fzf \
  net-tools iproute2 dnsutils nmap tcpdump iputils-ping \
  ufw fail2ban

sudo systemctl start fail2ban
sudo systemctl enable fail2ban

# =========================
# Languages & Runtimes
# =========================
sudo apt install -yq \
  python3 python3-pip \
  openjdk-11-jdk \
  nodejs npm

# =========================
# Containers & DevOps Tools
# =========================
sudo apt install -yq docker.io docker-compose
sudo systemctl enable --now docker

# Terraform (official repo)
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
sudo apt update -y
sudo apt install -y terraform

# Ansible
sudo apt install -y ansible

echo "All packages installed successfully."

# =========================
# Vim Config
# =========================
echo "[*] Writing Vim configuration to ~/.vimrc..."

cat << 'EOF' > ~/.vimrc
" =========================
"   Basic Vim Configuration
" =========================

" Enable syntax highlighting
syntax on

" Show absolute and relative line numbers
set number
set relativenumber

" Highlight the current line
set cursorline

" Highlight matching brackets
set showmatch

" Show (partial) command in the last line
set showcmd

" =========================
"   Indentation & Tabs
" =========================
set expandtab        " Use spaces instead of tabs
set tabstop=2        " Number of spaces that a <Tab> counts for
set shiftwidth=2     " Number of spaces to use for autoindent
set shiftround       " Round indent to nearest shiftwidth
set smartindent      " Smart autoindenting

" =========================
"   UI Enhancements
" =========================
set mouse=a          " Enable mouse support in all modes
set laststatus=2     " Always show status line
set hlsearch         " Highlight search results
set incsearch        " Incremental search
set ignorecase       " Case-insensitive searching
set smartcase        " ...unless capital letters are used
set wrap             " Wrap long lines
set scrolloff=5      " Keep 5 lines visible when scrolling
set signcolumn=yes   " Always show the sign column
EOF

echo "[*] Vim config installed at ~/.vimrc"
