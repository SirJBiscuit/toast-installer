#!/bin/bash

# Toast Installer Script
#
# This script automates the setup of a new node for the Pterodactyl Panel.
# It is designed for Debian-based systems (e.g., Debian 11/12, Ubuntu 20.04/22.04).
#
# WARNING: Always review scripts from the internet before running them on your system.

# --- Helper Functions and Colors ---
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'
readonly C_CYAN='\033[0;36m'
readonly C_BOLD='\033[1m'

# --- Global Variables ---
SSH_PORT=""
WINGS_PORT=""

log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
log_success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
log_warning() { echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"; }
log_error() { echo -e "${C_RED}[ERROR]${C_RESET} $1"; }

prompt_yes_no() {
    local prompt_text="$1"
    local response
    while true; do
        read -rp "$(echo -e "${C_YELLOW}[QUESTION]${C_RESET} ${prompt_text} (y/n): ")" response
        case "$response" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) log_warning "Please answer 'y' or 'n'.";;
        esac
    done
}

# --- Installation Functions ---

update_system() {
    log_info "--- System Update & Dependencies ---"
    if prompt_yes_no "Update system packages and install dependencies?"; then
        log_info "Updating package lists..." && apt-get update -y
        log_info "Upgrading existing packages..." && apt-get upgrade -y
        log_info "Installing required dependencies..." && apt-get install -y curl wget gnupg software-properties-common ufw
        log_success "System update and dependency installation complete."
    else
        log_warning "Skipping system update."
    fi
}

install_docker() {
    log_info "--- Docker Installation ---"
    if prompt_yes_no "Install Docker Engine?"; then
        log_info "Setting up Docker repository..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        log_info "Updating package lists for Docker..." && apt-get update -y
        log_info "Installing Docker packages..." && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        log_info "Enabling and starting Docker service..." && systemctl enable --now docker
        if systemctl is-active --quiet docker; then log_success "Docker is active and running. $(docker --version)"; else log_error "Docker service failed to start."; fi
    else
        log_warning "Skipping Docker installation."
    fi
}

harden_ssh() {
    log_info "--- SSH Hardening ---"
    if prompt_yes_no "Change the default SSH port?"; then
        while true; do
            read -rp "$(echo -e "${C_YELLOW}[QUESTION]${C_RESET} Enter new SSH port (1024-65535): ")" new_port_val
            if [[ "$new_port_val" -ge 1024 && "$new_port_val" -le 65535 ]]; then SSH_PORT=$new_port_val; break; else log_warning "Invalid port."; fi
        done
        log_info "Backing up /etc/ssh/sshd_config..." && cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
        log_info "Setting SSH port to $SSH_PORT..." && sed -i "s/^#*Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
        log_info "Restarting SSH service..." && systemctl restart sshd
        if systemctl is-active --quiet sshd; then log_success "SSH service restarted on port $SSH_PORT."; log_warning "Use 'ssh -p $SSH_PORT user@host' to connect."; else log_error "SSH service failed to restart."; fi
    else
        log_warning "Skipping SSH hardening."
    fi
}

install_wings() {
    log_info "--- Pterodactyl Wings Installation ---"
    if prompt_yes_no "Install Pterodactyl Wings?"; then
        read -rp "$(echo -e "${C_YELLOW}[QUESTION]${C_RESET} Enter Wings listen port (default: 8080): ")" -i "8080" -e WINGS_PORT
        log_info "Creating required directories..." && mkdir -p /etc/pterodactyl
        log_warning "Go to your Pterodactyl Panel, create a Node, and copy the configuration."
        log_warning "Paste the contents of 'config.yml' below, then press Ctrl+D."
        cat > /etc/pterodactyl/config.yml
        if [ ! -s /etc/pterodactyl/config.yml ]; then log_error "Config file is empty. Aborting."; return 1; fi
        log_info "Downloading Wings..." && curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" && chmod +x /usr/local/bin/wings
        log_info "Creating Wings systemd service..."
        cat > /etc/systemd/system/wings.service <<-EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=600
[Install]
WantedBy=multi-user.target
EOF
        log_info "Enabling and starting Wings service..." && systemctl enable --now wings
        log_info "Waiting for Wings to start..." && sleep 5
        if systemctl is-active --quiet wings; then log_success "Wings service is active and running."; else log_error "Wings service failed to start. Check 'journalctl -u wings'."; fi
    else
        log_warning "Skipping Wings installation."
    fi
}

configure_firewall() {
    log_info "--- Firewall (UFW) Configuration ---"
    if prompt_yes_no "Configure UFW firewall?"; then
        log_info "Resetting UFW to defaults..." && echo "y" | ufw reset
        if [ -z "$SSH_PORT" ]; then SSH_PORT=$(grep -E "^#*Port " /etc/ssh/sshd_config | awk '{print $2}' | head -n 1); [ -z "$SSH_PORT" ] && SSH_PORT=22; fi
        log_info "Allowing SSH on port $SSH_PORT..." && ufw allow "$SSH_PORT"/tcp
        if [ -z "$WINGS_PORT" ]; then WINGS_PORT=8080; log_warning "Wings port not set, defaulting to 8080."; fi
        log_info "Allowing Pterodactyl Wings ports ($WINGS_PORT/tcp, 2022/tcp)..." && ufw allow "$WINGS_PORT"/tcp && ufw allow 2022/tcp
        log_info "Enabling UFW..." && echo "y" | ufw enable
        log_success "Firewall configured and enabled." && ufw status
    else
        log_warning "Skipping firewall configuration."
    fi
}

install_fail2ban() {
    log_info "--- Install Fail2ban ---"
    if prompt_yes_no "Install Fail2ban to protect against brute-force attacks?"; then
        log_info "Installing Fail2ban..." && apt-get install -y fail2ban
        log_info "Enabling and starting Fail2ban..." && systemctl enable --now fail2ban
        if systemctl is-active --quiet fail2ban; then log_success "Fail2ban is active and running."; else log_error "Fail2ban service failed to start."; fi
    else
        log_warning "Skipping Fail2ban installation."
    fi
}

configure_swap() {
    log_info "--- Configure Swap File ---"
    if prompt_yes_no "Configure a swap file?"; then
        if [ "$(swapon --show)" ]; then log_warning "Swap space is already active. Skipping."; return; fi
        read -rp "$(echo -e "${C_YELLOW}[QUESTION]${C_RESET} Enter swap size in Gigabytes (e.g., 4): ")" -i "4" -e swap_size
        log_info "Creating a ${swap_size}G swap file..." && fallocate -l "${swap_size}G" /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
        log_info "Making swap file permanent..." && echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
        log_success "Swap file created and enabled." && free -h
    else
        log_warning "Skipping swap file configuration."
    fi
}

install_common_utils() {
    log_info "--- Install Common Utilities ---"
    if prompt_yes_no "Install helpful utilities (htop, ncdu, unzip, zip)?"; then
        log_info "Installing utilities..." && apt-get install -y htop ncdu unzip zip
        log_success "Common utilities installed."
    else
        log_warning "Skipping utility installation."
    fi
}

configure_auto_updates() {
    log_info "--- Configure Automatic Security Updates ---"
    if prompt_yes_no "Enable automatic security updates?"; then
        log_info "Installing unattended-upgrades package..." && apt-get install -y unattended-upgrades
        log_info "Configuring auto-upgrades..."
        cat > /etc/apt/apt.conf.d/20auto-upgrades <<-EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
        log_success "Automatic security updates have been enabled."
    else
        log_warning "Skipping automatic updates configuration."
    fi
}

tune_performance() {
    log_info "--- Apply Performance Tuning ---"
    if prompt_yes_no "Apply a performance tuning profile?"; then
        log_info "Installing tuned..." && apt-get install -y tuned
        log_info "Enabling and starting tuned service..." && systemctl enable --now tuned
        log_info "Applying 'virtual-host' profile for network/disk performance..." && tuned-adm profile virtual-host
        if systemctl is-active --quiet tuned; then log_success "Tuned is active. Current profile: $(tuned-adm active | grep 'Current active profile' | cut -d: -f2)"; else log_error "Tuned service failed to start."; fi
    else
        log_warning "Skipping performance tuning."
    fi
}

show_help() {
    clear
    echo -e "${C_CYAN}${C_BOLD}--- Help: Explanation of Steps ---${C_RESET}"
    echo -e "${C_YELLOW}Update System:${C_RESET} Synchronizes and upgrades all system packages to their latest versions. Essential for security and stability."
    echo -e "${C_YELLOW}Install Docker:${C_RESET} Installs the Docker container engine, which is required by Pterodactyl Wings to run game servers in isolated environments."
    echo -e "${C_YELLOW}Harden SSH:${C_RESET} Changes the default SSH port (22) to a custom one, reducing exposure to automated bots that scan for open SSH ports."
    echo -e "${C_YELLOW}Install Wings:${C_RESET} Installs the Pterodactyl Wings daemon, the software that connects this node to your control panel to manage servers."
    echo -e "${C_YELLOW}Configure Firewall:${C_RESET} Sets up UFW (Uncomplicated Firewall) to block all incoming traffic except for essential ports (SSH, Wings)."
    echo -e "${C_YELLOW}Install Fail2ban:${C_RESET} A security tool that monitors for repeated login failures and automatically bans the offending IP addresses to prevent brute-force attacks."
    echo -e "${C_YELLOW}Configure Swap:${C_RESET} Creates a swap file, which acts as virtual RAM. This helps prevent servers from crashing if the physical RAM is fully used."
    echo -e "${C_YELLOW}Install Common Utilities:${C_RESET} Installs a bundle of useful tools for server management: htop (process viewer), ncdu (disk usage analyzer), and zip/unzip."
    echo -e "${C_YELLOW}Auto Security Updates:${C_RESET} Configures the system to automatically download and install security-related package updates, keeping the node secure over time."
    echo -e "${C_YELLOW}Performance Tuning:${C_RESET} Installs and applies a system profile optimized for virtualization and network throughput, which can improve server performance."
    echo -e "\nPress any key to return to the main menu..."
    read -n 1 -s -r
}

# --- Main Script Logic ---

main_menu() {
    while true; do
        clear
        echo -e "${C_CYAN}"
        echo ' ________   ______    ______    ______  ________ '
        echo '|        \ /      \  /      \  /      \|        \'
        echo ' \$$$$$$$$|  $$$$$$\|  $$$$$$\|  $$$$$$\\$$$$$$$$'
        echo '   | $$   | $$  | $$| $$__| $$| $$___\$$  | $$   '
        echo '   | $$   | $$  | $$| $$    $$ \$$    \   | $$   '
        echo '   | $$   | $$  | $$| $$$$$$$$ _\$$$$$$\  | $$   '
        echo '   | $$   | $$__/ $$| $$  | $$|  \__| $$  | $$   '
        echo '   | $$    \$$    $$| $$  | $$ \$$    $$  | $$   '
        echo '    \$$     \$$$$$$  \$$   \$$  \$$$$$$    \$$   '
        echo -e "\n               Node Installer${C_RESET}\n"
        
        log_info "This script will guide you through setting up a new Pterodactyl node."
        
        PS3=$'\n'"Please choose an option: "
        options=(
            "Run all core steps"
            "Update System & Dependencies"
            "Install Docker"
            "Harden SSH Port"
            "Install Pterodactyl Wings"
            "Configure Firewall (UFW)"
            "Install Fail2ban (Security)"
            "Configure Swap (Stability)"
            "Install Common Utilities"
            "Configure Auto Security Updates"
            "Apply Performance Tuning"
            "Help / Explain All Steps"
            "Exit"
        )
        
        select opt in "${options[@]}"; do
            case "$opt" in
                "Run all core steps") update_system; install_docker; harden_ssh; install_wings; configure_firewall; break;;
                "Update System & Dependencies") update_system; break;;
                "Install Docker") install_docker; break;;
                "Harden SSH Port") harden_ssh; break;;
                "Install Pterodactyl Wings") install_wings; break;;
                "Configure Firewall (UFW)") configure_firewall; break;;
                "Install Fail2ban (Security)") install_fail2ban; break;;
                "Configure Swap (Stability)") configure_swap; break;;
                "Install Common Utilities") install_common_utils; break;;
                "Configure Auto Security Updates") configure_auto_updates; break;;
                "Apply Performance Tuning") tune_performance; break;;
                "Help / Explain All Steps") show_help; break;;
                "Exit") exit 0;;
                *) log_warning "Invalid option \$REPLY. Please try again.";;
            esac
        done
        log_success "\nTask finished. Returning to the main menu."
        sleep 2
    done
}

# --- Script Entrypoint ---
main_menu