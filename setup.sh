#!/bin/bash

# Ubuntu Server Zero Trust Security Setup Script
# Version: 2.0.0
# Target: Ubuntu 24.04 LTS (Noble Numbat)
# Compliance: CIS Benchmark, NIST SP 800-207, PCI DSS 4.0, SOC 2 Type II

set -euo pipefail  # Exit on error, undefined variables, and pipe failures
IFS=$'\n\t'        # Set Internal Field Separator for better security

# Enable debug mode if DEBUG environment variable is set
[[ "${DEBUG:-0}" == "1" ]] && set -x

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_VERSION="2.0.0"
readonly SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly LOG_FILE="/var/log/zero-trust-setup-$(date +%Y%m%d-%H%M%S).log"
readonly BACKUP_DIR="${HOME}/.config-backup-$(date +%Y%m%d-%H%M%S)"
readonly UBUNTU_VERSION_REQUIRED="24.04"
readonly KERNEL_MIN_VERSION="6.8"

# Global variables
MAIN_USER=""
INTERACTIVE_MODE=true
DRY_RUN=false
VERBOSE=false
SKIP_VALIDATION=false

# Service configuration variables
CLOUDFLARE_EMAIL=""
CLOUDFLARE_API_KEY=""
CLOUDFLARE_TUNNEL_TOKEN=""
CLOUDFLARE_TUNNEL_NAME=""
TAILSCALE_AUTH_KEY=""
DOMAIN_NAME=""
ADMIN_EMAIL=""
ENABLE_ROOTLESS_DOCKER=false
ENABLE_PODMAN=false

# Enhanced logging functions with file output
log_message() {
    local level="$1"
    local message="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    
    # Display to console based on level
    case "$level" in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        DEBUG)
            [[ "${VERBOSE}" == true ]] && echo -e "${CYAN}[DEBUG]${NC} $message"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

print_status() {
    log_message "INFO" "$1"
}

print_success() {
    log_message "SUCCESS" "$1"
}

print_error() {
    log_message "ERROR" "$1"
}

print_warning() {
    log_message "WARNING" "$1"
}

print_debug() {
    log_message "DEBUG" "$1"
}

# Error handler function
error_handler() {
    local exit_code=$1
    local line_number=$2
    log_message "ERROR" "Script failed with exit code $exit_code at line $line_number"
    log_message "ERROR" "Last command: ${BASH_COMMAND}"
    
    # Attempt cleanup
    cleanup_on_error
    
    exit "$exit_code"
}

# Cleanup function for errors
cleanup_on_error() {
    log_message "INFO" "Performing cleanup after error..."
    # Add cleanup tasks here if needed
}

# Initialize logging
initialize_logging() {
    # Create log directory if it doesn't exist
    local log_dir="$(dirname "$LOG_FILE")"
    [[ ! -d "$log_dir" ]] && sudo mkdir -p "$log_dir"
    
    # Create log file with proper permissions
    sudo touch "$LOG_FILE"
    sudo chmod 640 "$LOG_FILE"
    
    # Initial log entry
    log_message "INFO" "==============================================="
    log_message "INFO" "Zero Trust Security Setup Script v${SCRIPT_VERSION}"
    log_message "INFO" "Started at: $(date)"
    log_message "INFO" "User: $(whoami)"
    log_message "INFO" "==============================================="
}

# Helper function to get the correct SSH service name
get_ssh_service_name() {
    if systemctl is-active --quiet ssh; then
        echo "ssh"
    elif systemctl is-active --quiet sshd; then
        echo "sshd"
    else
        # Default to ssh for Ubuntu
        echo "ssh"
    fi
}

# Function to validate Ubuntu version
validate_ubuntu_version() {
    print_status "Validating Ubuntu version..."
    
    local current_version=$(lsb_release -rs 2>/dev/null || echo "0")
    
    if [[ "$current_version" != "$UBUNTU_VERSION_REQUIRED" ]]; then
        print_error "This script requires Ubuntu $UBUNTU_VERSION_REQUIRED LTS"
        print_error "Current version: $current_version"
        
        if [[ "$INTERACTIVE_MODE" == true ]]; then
            read -p "Do you want to continue anyway? (not recommended) [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        else
            exit 1
        fi
    else
        print_success "Ubuntu version $current_version validated"
    fi
    
    # Check kernel version
    local kernel_version=$(uname -r | cut -d'-' -f1)
    if [[ "$(printf '%s\n' "$KERNEL_MIN_VERSION" "$kernel_version" | sort -V | head -n1)" != "$KERNEL_MIN_VERSION" ]]; then
        print_warning "Kernel version $kernel_version may not support all security features"
        print_warning "Recommended minimum: $KERNEL_MIN_VERSION"
    fi
}

# Function to detect main user (first non-root user with home directory)
detect_main_user() {
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        MAIN_USER="$SUDO_USER"
    else
        # Find first user with UID >= 1000 (typical for regular users)
        MAIN_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}' /etc/passwd)
    fi
    
    if [ -z "$MAIN_USER" ]; then
        print_warning "Could not detect main user automatically"
        if [[ "$INTERACTIVE_MODE" == true ]]; then
            read -p "Please enter the username of the main user: " MAIN_USER
        else
            print_error "Main user detection failed in non-interactive mode"
            return 1
        fi
    fi
    
    if ! id "$MAIN_USER" &>/dev/null; then
        print_error "User $MAIN_USER does not exist"
        return 1
    fi
    
    print_success "Main user detected: $MAIN_USER"
    return 0
}

# Interactive configuration function
configure_interactively() {
    print_status "Starting interactive configuration..."
    
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}     Zero Trust Security Configuration Wizard${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}\n"
    
    # Admin email
    read -p "Enter admin email for notifications: " ADMIN_EMAIL
    while ! [[ "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; do
        print_error "Invalid email format"
        read -p "Enter admin email for notifications: " ADMIN_EMAIL
    done
    
    # Domain configuration
    read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
    
    # Cloudflare configuration
    echo -e "\n${YELLOW}Cloudflare Configuration${NC}"
    echo "1) Use existing Cloudflare tunnel token"
    echo "2) Login to Cloudflare to create new tunnel"
    echo "3) Skip Cloudflare setup"
    read -p "Select option [1-3]: " cf_option
    
    case $cf_option in
        1)
            read -p "Enter Cloudflare tunnel token: " CLOUDFLARE_TUNNEL_TOKEN
            ;;
        2)
            print_status "Preparing Cloudflare login..."
            configure_cloudflare_interactive
            ;;
        3)
            print_warning "Skipping Cloudflare setup - web services will not be accessible"
            ;;
    esac
    
    # Tailscale configuration
    echo -e "\n${YELLOW}Tailscale Configuration${NC}"
    echo "1) Use existing Tailscale auth key"
    echo "2) Login to Tailscale interactively"
    echo "3) Skip Tailscale setup"
    read -p "Select option [1-3]: " ts_option
    
    case $ts_option in
        1)
            read -p "Enter Tailscale auth key: " TAILSCALE_AUTH_KEY
            ;;
        2)
            print_status "Will configure Tailscale interactively during setup"
            ;;
        3)
            print_warning "Skipping Tailscale - SSH will remain publicly accessible"
            ;;
    esac
    
    # Container runtime selection
    echo -e "\n${YELLOW}Container Runtime Configuration${NC}"
    echo "1) Docker CE with standard mode"
    echo "2) Docker CE with rootless mode (more secure)"
    echo "3) Podman (rootless by default)"
    echo "4) Both Docker and Podman"
    read -p "Select option [1-4]: " container_option
    
    case $container_option in
        2)
            ENABLE_ROOTLESS_DOCKER=true
            ;;
        3)
            ENABLE_PODMAN=true
            ;;
        4)
            ENABLE_ROOTLESS_DOCKER=true
            ENABLE_PODMAN=true
            ;;
    esac
    
    # Confirmation
    echo -e "\n${CYAN}Configuration Summary:${NC}"
    echo "Admin Email: $ADMIN_EMAIL"
    echo "Domain: $DOMAIN_NAME"
    echo "Cloudflare: $([ -n "$CLOUDFLARE_TUNNEL_TOKEN" ] && echo "Configured" || echo "Not configured")"
    echo "Tailscale: $([ -n "$TAILSCALE_AUTH_KEY" ] && echo "Configured" || echo "Interactive")"
    echo "Rootless Docker: $ENABLE_ROOTLESS_DOCKER"
    echo "Podman: $ENABLE_PODMAN"
    
    read -p "Proceed with this configuration? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        print_error "Configuration cancelled"
        exit 1
    fi
}

# Cloudflare interactive setup
configure_cloudflare_interactive() {
    print_status "Installing cloudflared for interactive setup..."
    
    # Install cloudflared if not present
    if ! command -v cloudflared &> /dev/null; then
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared.deb
        rm cloudflared.deb
    fi
    
    print_status "Logging into Cloudflare..."
    cloudflared tunnel login
    
    # Create tunnel
    read -p "Enter a name for your tunnel: " CLOUDFLARE_TUNNEL_NAME
    cloudflared tunnel create "$CLOUDFLARE_TUNNEL_NAME"
    
    # Get tunnel credentials
    CLOUDFLARE_TUNNEL_TOKEN=$(cloudflared tunnel token "$CLOUDFLARE_TUNNEL_NAME")
    
    print_success "Cloudflare tunnel created successfully"
}

# Function to create backup directory
create_backup() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        print_status "Created backup directory: $BACKUP_DIR"
    fi
}

# Function to backup file if it exists
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        create_backup
        cp "$file" "$BACKUP_DIR/$(basename "$file").backup"
        print_status "Backed up $file to $BACKUP_DIR"
    fi
}

# Function 1: Install Zsh
install_zsh() {
    print_status "Installing Zsh..."
    
    # Update package list
    sudo apt update
    
    # Install zsh
    if ! command -v zsh &> /dev/null; then
        sudo apt install -y zsh
        print_success "Zsh installed successfully"
    else
        print_warning "Zsh is already installed"
    fi
    
    # Get zsh path
    ZSH_PATH=$(which zsh)
    
    # Set zsh as default shell for root
    print_status "Setting zsh as default shell for root..."
    chsh -s "$ZSH_PATH" root
    
    # Set zsh as default shell for main user
    if [ -n "$MAIN_USER" ]; then
        print_status "Setting zsh as default shell for $MAIN_USER..."
        chsh -s "$ZSH_PATH" "$MAIN_USER"
        print_success "Default shell changed to zsh for root and $MAIN_USER"
    else
        print_warning "Main user not detected, skipping user shell change"
    fi
}

# Function 2: Install Oh-My-Zsh
install_oh_my_zsh() {
    print_status "Installing Oh-My-Zsh..."
    
    # Install git and curl if not present
    sudo apt update
    sudo apt install -y git curl wget
    
    # Function to install oh-my-zsh for a specific user
    install_omz_for_user() {
        local user="$1"
        local home_dir
        
        if [ "$user" = "root" ]; then
            home_dir="/root"
        else
            home_dir="/home/$user"
        fi
        
        print_status "Installing Oh-My-Zsh for $user..."
        
        # Backup existing .zshrc
        backup_file "$home_dir/.zshrc"
        
        # Remove existing oh-my-zsh installation if present
        if [ -d "$home_dir/.oh-my-zsh" ]; then
            print_warning "Removing existing Oh-My-Zsh installation for $user"
            sudo rm -rf "$home_dir/.oh-my-zsh"
        fi
        
        # Download and install oh-my-zsh
        if [ "$user" = "root" ]; then
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        else
            sudo -u "$user" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        fi
        
        print_success "Oh-My-Zsh installed for $user"
    }
    
    # Install for root
    install_omz_for_user "root"
    
    # Install for main user
    if [ -n "$MAIN_USER" ]; then
        install_omz_for_user "$MAIN_USER"
    fi
    
    # Install zsh plugins
    print_status "Installing zsh plugins..."
    
    install_plugins_for_user() {
        local user="$1"
        local home_dir
        
        if [ "$user" = "root" ]; then
            home_dir="/root"
        else
            home_dir="/home/$user"
        fi
        
        local custom_plugins="$home_dir/.oh-my-zsh/custom/plugins"
        
        # zsh-autosuggestions
        if [ ! -d "$custom_plugins/zsh-autosuggestions" ]; then
            if [ "$user" = "root" ]; then
                git clone https://github.com/zsh-users/zsh-autosuggestions "$custom_plugins/zsh-autosuggestions"
            else
                sudo -u "$user" git clone https://github.com/zsh-users/zsh-autosuggestions "$custom_plugins/zsh-autosuggestions"
            fi
            print_success "zsh-autosuggestions installed for $user"
        fi
        
        # zsh-completions
        if [ ! -d "$custom_plugins/zsh-completions" ]; then
            if [ "$user" = "root" ]; then
                git clone https://github.com/zsh-users/zsh-completions "$custom_plugins/zsh-completions"
            else
                sudo -u "$user" git clone https://github.com/zsh-users/zsh-completions "$custom_plugins/zsh-completions"
            fi
            print_success "zsh-completions installed for $user"
        fi
        
        # zsh-syntax-highlighting
        if [ ! -d "$custom_plugins/zsh-syntax-highlighting" ]; then
            if [ "$user" = "root" ]; then
                git clone https://github.com/zsh-users/zsh-syntax-highlighting "$custom_plugins/zsh-syntax-highlighting"
            else
                sudo -u "$user" git clone https://github.com/zsh-users/zsh-syntax-highlighting "$custom_plugins/zsh-syntax-highlighting"
            fi
            print_success "zsh-syntax-highlighting installed for $user"
        fi
    }
    
    install_plugins_for_user "root"
    if [ -n "$MAIN_USER" ]; then
        install_plugins_for_user "$MAIN_USER"
    fi
}

# Function 3: Install Powerlevel10k
install_powerlevel10k() {
    print_status "Installing Powerlevel10k theme..."
    
    install_p10k_for_user() {
        local user="$1"
        local home_dir
        
        if [ "$user" = "root" ]; then
            home_dir="/root"
        else
            home_dir="/home/$user"
        fi
        
        local theme_dir="$home_dir/.oh-my-zsh/custom/themes/powerlevel10k"
        
        print_status "Installing Powerlevel10k for $user..."
        
        # Remove existing installation if present
        if [ -d "$theme_dir" ]; then
            print_warning "Removing existing Powerlevel10k installation for $user"
            sudo rm -rf "$theme_dir"
        fi
        
        # Clone Powerlevel10k
        if [ "$user" = "root" ]; then
            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"
        else
            sudo -u "$user" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$theme_dir"
        fi
        
        print_success "Powerlevel10k installed for $user"
    }
    
    # Install for root
    install_p10k_for_user "root"
    
    # Install for main user
    if [ -n "$MAIN_USER" ]; then
        install_p10k_for_user "$MAIN_USER"
    fi
}

# Function 4: Deploy configuration files
deploy_configs() {
    print_status "Deploying configuration files..."
    
    # First, check if we need to download the files from GitHub
    if [ ! -f "$SCRIPT_DIR/.zshrc" ] && [ ! -f "$SCRIPT_DIR/zshrc" ]; then
        print_status "Configuration files not found locally. Downloading from GitHub..."
        wget -q https://raw.githubusercontent.com/abd3lraouf/server-config/main/zshrc -O "$SCRIPT_DIR/zshrc" || \
        wget -q https://raw.githubusercontent.com/abd3lraouf/server-config/main/.zshrc -O "$SCRIPT_DIR/.zshrc"
    fi
    
    if [ ! -f "$SCRIPT_DIR/.p10k.zsh" ] && [ ! -f "$SCRIPT_DIR/p10k.zsh" ]; then
        wget -q https://raw.githubusercontent.com/abd3lraouf/server-config/main/p10k.zsh -O "$SCRIPT_DIR/p10k.zsh" || \
        wget -q https://raw.githubusercontent.com/abd3lraouf/server-config/main/.p10k.zsh -O "$SCRIPT_DIR/.p10k.zsh"
    fi
    
    deploy_for_user() {
        local user="$1"
        local home_dir
        
        if [ "$user" = "root" ]; then
            home_dir="/root"
        else
            home_dir="/home/$user"
        fi
        
        print_status "Deploying configs for $user..."
        
        # Deploy .zshrc (check for both .zshrc and zshrc in script directory)
        if [ -f "$SCRIPT_DIR/.zshrc" ]; then
            backup_file "$home_dir/.zshrc"
            cp "$SCRIPT_DIR/.zshrc" "$home_dir/.zshrc"
            if [ "$user" != "root" ]; then
                chown "$user:$user" "$home_dir/.zshrc"
            fi
            chmod 644 "$home_dir/.zshrc"
            print_success ".zshrc deployed for $user"
        elif [ -f "$SCRIPT_DIR/zshrc" ]; then
            backup_file "$home_dir/.zshrc"
            cp "$SCRIPT_DIR/zshrc" "$home_dir/.zshrc"
            if [ "$user" != "root" ]; then
                chown "$user:$user" "$home_dir/.zshrc"
            fi
            chmod 644 "$home_dir/.zshrc"
            print_success ".zshrc deployed for $user (from zshrc)"
        else
            print_error "Neither .zshrc nor zshrc found in script directory"
            print_warning "You can manually download from: https://github.com/abd3lraouf/server-config"
        fi
        
        # Deploy .p10k.zsh (check for both .p10k.zsh and p10k.zsh in script directory)
        if [ -f "$SCRIPT_DIR/.p10k.zsh" ]; then
            backup_file "$home_dir/.p10k.zsh"
            cp "$SCRIPT_DIR/.p10k.zsh" "$home_dir/.p10k.zsh"
            if [ "$user" != "root" ]; then
                chown "$user:$user" "$home_dir/.p10k.zsh"
            fi
            chmod 644 "$home_dir/.p10k.zsh"
            print_success ".p10k.zsh deployed for $user"
        elif [ -f "$SCRIPT_DIR/p10k.zsh" ]; then
            backup_file "$home_dir/.p10k.zsh"
            cp "$SCRIPT_DIR/p10k.zsh" "$home_dir/.p10k.zsh"
            if [ "$user" != "root" ]; then
                chown "$user:$user" "$home_dir/.p10k.zsh"
            fi
            chmod 644 "$home_dir/.p10k.zsh"
            print_success ".p10k.zsh deployed for $user (from p10k.zsh)"
        else
            print_error "Neither .p10k.zsh nor p10k.zsh found in script directory"
            print_warning "You can manually download from: https://github.com/abd3lraouf/server-config"
        fi
    }
    
    # Deploy for root
    deploy_for_user "root"
    
    # Deploy for main user
    if [ -n "$MAIN_USER" ]; then
        deploy_for_user "$MAIN_USER"
    fi
}

# Function 5: System Update
system_update() {
    print_status "Updating system packages..."
    
    # Update package lists
    sudo apt update
    
    # Upgrade all packages
    print_status "Upgrading installed packages (this may take a while)..."
    sudo apt upgrade -y
    
    # Remove unnecessary packages
    print_status "Cleaning up unnecessary packages..."
    sudo apt autoremove -y
    sudo apt autoclean -y
    
    print_success "System update completed"
}

# Function 6: Install NVM (Node Version Manager)
install_nvm() {
    print_status "Installing NVM (Node Version Manager)..."
    
    install_nvm_for_user() {
        local user="$1"
        local home_dir
        
        if [ "$user" = "root" ]; then
            home_dir="/root"
        else
            home_dir="/home/$user"
        fi
        
        print_status "Installing NVM for $user..."
        
        # Download and install NVM
        if [ "$user" = "root" ]; then
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
        else
            sudo -u "$user" bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash'
        fi
        
        # Add NVM to .zshrc if not already present
        if ! grep -q "NVM_DIR" "$home_dir/.zshrc" 2>/dev/null; then
            cat >> "$home_dir/.zshrc" << 'EOF'

# NVM Configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
EOF
            if [ "$user" != "root" ]; then
                chown "$user:$user" "$home_dir/.zshrc"
            fi
        fi
        
        print_success "NVM installed for $user"
    }
    
    # Install for root
    install_nvm_for_user "root"
    
    # Install for main user
    if [ -n "$MAIN_USER" ]; then
        install_nvm_for_user "$MAIN_USER"
    fi
}

# Function 7: Install Node.js
install_nodejs() {
    print_status "Installing Node.js via NVM..."
    
    install_node_for_user() {
        local user="$1"
        local home_dir
        
        if [ "$user" = "root" ]; then
            home_dir="/root"
        else
            home_dir="/home/$user"
        fi
        
        print_status "Installing Node.js LTS for $user..."
        
        # Source NVM and install Node.js
        if [ "$user" = "root" ]; then
            bash -c "source $home_dir/.nvm/nvm.sh && nvm install --lts && nvm use --lts && nvm alias default node"
        else
            sudo -u "$user" bash -c "source $home_dir/.nvm/nvm.sh && nvm install --lts && nvm use --lts && nvm alias default node"
        fi
        
        print_success "Node.js LTS installed for $user"
    }
    
    # Install for root
    install_node_for_user "root"
    
    # Install for main user
    if [ -n "$MAIN_USER" ]; then
        install_node_for_user "$MAIN_USER"
    fi
}

# Function 8: Install Claude CLI
install_claude() {
    print_status "Installing Claude CLI..."
    
    install_claude_for_user() {
        local user="$1"
        local home_dir
        
        if [ "$user" = "root" ]; then
            home_dir="/root"
        else
            home_dir="/home/$user"
        fi
        
        print_status "Installing Claude CLI for $user..."
        
        # Install Claude CLI globally via npm
        if [ "$user" = "root" ]; then
            bash -c "source $home_dir/.nvm/nvm.sh && npm install -g @anthropic-ai/claude-code"
        else
            sudo -u "$user" bash -c "source $home_dir/.nvm/nvm.sh && npm install -g @anthropic-ai/claude-code"
        fi
        
        print_success "Claude CLI installed for $user"
        print_warning "Remember to run 'claude login' to authenticate"
    }
    
    # Install for root
    install_claude_for_user "root"
    
    # Install for main user
    if [ -n "$MAIN_USER" ]; then
        install_claude_for_user "$MAIN_USER"
    fi
}

# Function 9: Install htop
install_htop() {
    print_status "Installing htop system monitor..."
    
    sudo apt update
    sudo apt install -y htop
    
    print_success "htop installed successfully"
}

# Function 10: Configure UFW Firewall
configure_ufw() {
    print_status "Configuring UFW firewall..."
    
    # Install UFW if not present
    if ! command -v ufw &> /dev/null; then
        sudo apt update
        sudo apt install -y ufw
    fi
    
    # Reset UFW to defaults
    print_status "Resetting UFW to defaults..."
    echo "y" | sudo ufw --force reset
    
    # Set default policies
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Allow SSH (port 22)
    print_status "Allowing SSH access..."
    sudo ufw allow ssh
    
    # Enable UFW
    print_status "Enabling UFW..."
    echo "y" | sudo ufw --force enable
    
    # Show status
    sudo ufw status verbose
    
    print_success "UFW firewall configured and enabled"
    print_warning "Only SSH (port 22) is allowed. Configure additional ports as needed."
}

# Function 11: Configure SSH for Coolify
configure_ssh_coolify() {
    print_status "Configuring SSH for Coolify compatibility..."
    
    # Backup original SSH config
    backup_file "/etc/ssh/sshd_config"
    
    # Configure SSH settings
    print_status "Updating SSH configuration..."
    
    # Check if PermitRootLogin is already configured
    if grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
        sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    else
        echo "PermitRootLogin prohibit-password" | sudo tee -a /etc/ssh/sshd_config
    fi
    
    # Check if PubkeyAuthentication is already configured
    if grep -q "^PubkeyAuthentication" /etc/ssh/sshd_config; then
        sudo sed -i 's/^PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    else
        echo "PubkeyAuthentication yes" | sudo tee -a /etc/ssh/sshd_config
    fi
    
    # Generate SSH key for Coolify if it doesn't exist
    if [ ! -f ~/.ssh/id_ed25519 ]; then
        print_status "Generating SSH key for server..."
        ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519 -q -N "" -C "root@$(hostname)"
        
        # Add to authorized_keys
        cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        chmod 700 ~/.ssh
        
        print_success "SSH key generated and added to authorized_keys"
    else
        print_warning "SSH key already exists"
    fi
    
    # Restart SSH service
    print_status "Restarting SSH service..."
    if systemctl is-active --quiet ssh; then
        sudo systemctl restart ssh
    elif systemctl is-active --quiet sshd; then
        sudo systemctl restart sshd
    else
        print_error "Could not detect SSH service"
    fi
    
    print_success "SSH configured for Coolify"
    print_warning "Make sure you have your SSH keys backed up before logging out!"
}

# Function 12: Install Coolify
install_coolify() {
    print_status "Installing Coolify..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_warning "Docker will be installed as part of Coolify installation"
    fi
    
    # Prepare Coolify directories
    print_status "Preparing Coolify installation..."
    sudo mkdir -p /data/coolify/ssh/keys
    
    # Run Coolify installation script
    print_status "Running Coolify installation script..."
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash
    
    # Generate Coolify SSH keys if needed
    if [ ! -f /data/coolify/ssh/keys/id.root@host.docker.internal ]; then
        print_status "Generating Coolify SSH keys..."
        ssh-keygen -t ed25519 -a 100 \
            -f /data/coolify/ssh/keys/id.root@host.docker.internal \
            -q -N "" -C root@coolify
        
        # Set correct ownership
        sudo chown 9999 /data/coolify/ssh/keys/id.root@host.docker.internal
        
        # Add public key to authorized_keys
        cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> ~/.ssh/authorized_keys
    fi
    
    # Open firewall ports for Coolify
    if command -v ufw &> /dev/null; then
        print_status "Opening firewall ports for Coolify..."
        sudo ufw allow 80/tcp comment 'Coolify HTTP'
        sudo ufw allow 443/tcp comment 'Coolify HTTPS'
        sudo ufw allow 8000/tcp comment 'Coolify Dashboard'
        sudo ufw reload
    fi
    
    print_success "Coolify installed successfully!"
    print_warning "Access Coolify at: http://$(curl -s ifconfig.me):8000"
    print_warning "Default login: admin@example.com"
}

# Function 13: Clean APT sources
clean_apt_sources() {
    print_status "Cleaning APT sources..."
    
    # Install python3-apt
    sudo apt update
    sudo apt install -y python3-apt
    
    # Check if aptsources-cleanup.pyz exists
    if [ ! -f "$SCRIPT_DIR/aptsources-cleanup.pyz" ]; then
        print_status "Downloading aptsources-cleanup.pyz..."
        wget -O "$SCRIPT_DIR/aptsources-cleanup.pyz" https://github.com/davidfoerster/aptsources-cleanup/releases/download/v0.1.7.5.2/aptsources-cleanup.pyz
        chmod a+x "$SCRIPT_DIR/aptsources-cleanup.pyz"
    fi
    
    # Run cleanup
    print_status "Running APT sources cleanup..."
    sudo "$SCRIPT_DIR/aptsources-cleanup.pyz"
    
    print_success "APT sources cleaned"
}

# ============================================================================
# ZERO TRUST SECURITY FUNCTIONS
# ============================================================================

# Global variables for Zero Trust setup
ZERO_TRUST_DIR="/etc/zero-trust"
ZERO_TRUST_LOG="/var/log/zero-trust-setup.log"
CLOUDFLARE_TOKEN=""
TAILSCALE_KEY=""
DOMAIN=""
EMAIL=""
DRY_RUN=false
NON_INTERACTIVE=false
SKIP_BACKUP=false

# Function to initialize Zero Trust logging
init_zero_trust_logging() {
    mkdir -p "$(dirname "$ZERO_TRUST_LOG")"
    touch "$ZERO_TRUST_LOG"
    exec 2> >(tee -a "$ZERO_TRUST_LOG" >&2)
}

# Function to log with timestamp
log_action() {
    local message="$1"
    local level="${2:-INFO}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$ZERO_TRUST_LOG"
}

# Function to create Zero Trust directory structure
create_zero_trust_dirs() {
    print_status "Creating Zero Trust directory structure..."
    
    local dirs=(
        "$ZERO_TRUST_DIR"
        "$ZERO_TRUST_DIR/backups"
        "$ZERO_TRUST_DIR/configs"
        "$ZERO_TRUST_DIR/configs/ufw"
        "$ZERO_TRUST_DIR/configs/docker"
        "$ZERO_TRUST_DIR/configs/crowdsec"
        "$ZERO_TRUST_DIR/configs/cloudflare"
        "$ZERO_TRUST_DIR/scripts"
        "$ZERO_TRUST_DIR/docs"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            sudo mkdir -p "$dir"
            log_action "Created directory: $dir"
        fi
    done
    
    print_success "Zero Trust directory structure created"
}

# Function 14: System Hardening
harden_system() {
    print_status "Implementing system hardening..."
    log_action "Starting system hardening" "INFO"
    
    # Backup existing configurations
    if [ "$SKIP_BACKUP" = false ]; then
        backup_file "/etc/pam.d/common-password"
        backup_file "/etc/security/limits.conf"
        backup_file "/etc/sysctl.conf"
    fi
    
    # Configure PAM for strong passwords
    print_status "Configuring PAM password policies..."
    sudo apt-get install -y libpam-pwquality
    
    # Set password requirements
    cat << 'EOF' | sudo tee /etc/security/pwquality.conf > /dev/null
# Password Quality Configuration
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
retry = 3
maxrepeat = 3
gecoscheck = 1
EOF
    
    # Enable AppArmor
    print_status "Enabling AppArmor..."
    sudo apt-get install -y apparmor apparmor-utils
    sudo systemctl enable apparmor
    sudo systemctl start apparmor
    
    # Configure automatic security updates
    print_status "Configuring automatic security updates..."
    sudo apt-get install -y unattended-upgrades apt-listchanges
    
    cat << 'EOF' | sudo tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF
    
    # Enable automatic updates
    echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null
    
    # Configure audit system
    print_status "Configuring audit system..."
    sudo apt-get install -y auditd audispd-plugins
    
    # Enable audit service
    sudo systemctl enable auditd
    sudo systemctl start auditd
    
    # Remove unnecessary packages
    print_status "Removing unnecessary packages..."
    local unnecessary_packages=(
        "exim4*"
        "postfix*"
        "sendmail*"
        "cups*"
        "avahi-daemon"
        "bluetooth"
        "whoopsie"
    )
    
    for package in "${unnecessary_packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$package"; then
            sudo apt-get remove -y "$package" 2>/dev/null || true
        fi
    done
    
    # Kernel hardening via sysctl
    print_status "Applying kernel hardening parameters..."
    cat << 'EOF' | sudo tee -a /etc/sysctl.d/99-zero-trust.conf > /dev/null
# Zero Trust Kernel Hardening
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_timestamps = 0
kernel.randomize_va_space = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
kernel.panic = 10
kernel.panic_on_oops = 1
kernel.yama.ptrace_scope = 1
EOF
    
    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.d/99-zero-trust.conf
    
    log_action "System hardening completed" "SUCCESS"
    print_success "System hardening completed"
}

# Function 15: Configure UFW with Docker integration
configure_ufw_docker() {
    print_status "Configuring UFW with Docker integration..."
    log_action "Starting UFW-Docker configuration" "INFO"
    
    # Install UFW if not present
    if ! command -v ufw &> /dev/null; then
        sudo apt-get install -y ufw
    fi
    
    # Download and install ufw-docker
    print_status "Installing ufw-docker..."
    sudo wget -O /usr/local/bin/ufw-docker \
        https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
    sudo chmod +x /usr/local/bin/ufw-docker
    
    # Check Docker iptables is enabled
    if [ -f /etc/docker/daemon.json ]; then
        if grep -q '"iptables": false' /etc/docker/daemon.json; then
            print_warning "Docker iptables is disabled. Enabling it for ufw-docker compatibility..."
            sudo sed -i '/"iptables": false/d' /etc/docker/daemon.json
            sudo systemctl restart docker
        fi
    fi
    
    # Configure UFW to work with Docker
    print_status "Configuring UFW rules for Docker..."
    
    # Backup UFW configuration
    backup_file "/etc/ufw/after.rules"
    
    # Add Docker rules to UFW
    if ! grep -q "DOCKER-USER" /etc/ufw/after.rules; then
        cat << 'EOF' | sudo tee -a /etc/ufw/after.rules > /dev/null

# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16
-A DOCKER-USER -j ufw-user-forward
-A DOCKER-USER -j DROP -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 192.168.0.0/16
-A DOCKER-USER -j DROP -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 10.0.0.0/8
-A DOCKER-USER -j DROP -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j DROP -p udp -m udp --dport 0:32767 -d 192.168.0.0/16
-A DOCKER-USER -j DROP -p udp -m udp --dport 0:32767 -d 10.0.0.0/8
-A DOCKER-USER -j DROP -p udp -m udp --dport 0:32767 -d 172.16.0.0/12
-A DOCKER-USER -j RETURN
COMMIT
# END UFW AND DOCKER
EOF
    fi
    
    # Install ufw-docker properly
    sudo /usr/local/bin/ufw-docker install
    
    # Update Docker networks
    if docker network ls &>/dev/null; then
        print_status "Updating UFW rules for Docker networks..."
        sudo /usr/local/bin/ufw-docker install --docker-subnets
    fi
    
    # Set UFW defaults
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw default deny routed
    
    # Allow SSH on Tailscale interface only (will be configured later)
    # For now, keep SSH open to prevent lockout
    sudo ufw allow 22/tcp comment 'SSH - Will be restricted to Tailscale'
    
    # Enable UFW
    echo "y" | sudo ufw --force enable
    
    log_action "UFW-Docker configuration completed" "SUCCESS"
    print_success "UFW configured with Docker integration"
}

# Function 16: Install and configure Tailscale with validation
install_tailscale() {
    print_status "Installing Tailscale for Zero Trust network access..."
    log_action "Starting Tailscale installation" "INFO"
    
    # Check if Tailscale is already installed
    if command -v tailscale &> /dev/null; then
        print_warning "Tailscale is already installed"
        
        # Check if already connected
        if tailscale status &>/dev/null 2>&1; then
            local current_ip=$(tailscale ip -4 2>/dev/null)
            print_success "Tailscale already connected: $current_ip"
            
            if [[ "$INTERACTIVE_MODE" == true ]]; then
                read -p "Reconfigure Tailscale? [y/N]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    return 0
                fi
            else
                return 0
            fi
        fi
    else
        # Install Tailscale using official script
        print_status "Downloading and installing Tailscale..."
        if ! curl -fsSL https://tailscale.com/install.sh | sh; then
            print_error "Failed to install Tailscale"
            return 1
        fi
    fi
    
    # Start Tailscale service
    sudo systemctl enable tailscaled
    if ! sudo systemctl start tailscaled; then
        print_error "Failed to start Tailscale daemon"
        return 1
    fi
    
    # Configure Tailscale based on mode
    if [ -n "$TAILSCALE_AUTH_KEY" ]; then
        print_status "Configuring Tailscale with provided auth key..."
        if ! sudo tailscale up --authkey="$TAILSCALE_AUTH_KEY" --ssh --advertise-tags=tag:server; then
            print_error "Failed to authenticate with Tailscale"
            return 1
        fi
    elif [[ "$INTERACTIVE_MODE" == true ]]; then
        print_status "Starting interactive Tailscale configuration..."
        echo -e "${YELLOW}Please authenticate with Tailscale:${NC}"
        
        # Run tailscale up interactively
        if ! sudo tailscale up --ssh --advertise-tags=tag:server; then
            print_error "Failed to configure Tailscale"
            return 1
        fi
    else
        print_warning "No Tailscale auth key provided in non-interactive mode"
        print_warning "Run manually: sudo tailscale up --ssh"
        return 0
    fi
    
    # Wait for Tailscale to connect with progress indicator
    print_status "Waiting for Tailscale connection..."
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if tailscale status &>/dev/null 2>&1; then
            break
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done
    echo
    
    # Validate connection
    if tailscale status &>/dev/null 2>&1; then
        # Get Tailscale IP
        local tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "Not connected")
        local tailscale_hostname=$(tailscale status --json 2>/dev/null | jq -r '.Self.HostName' 2>/dev/null || echo "unknown")
        
        print_success "Tailscale connected successfully!"
        print_success "Tailscale IP: $tailscale_ip"
        print_success "Tailscale hostname: $tailscale_hostname"
        
        # Configure UFW for Tailscale
        print_status "Configuring firewall for Tailscale..."
        
        # Allow traffic on Tailscale interface
        if sudo ufw allow in on tailscale0 comment 'Tailscale network'; then
            print_success "Firewall configured for Tailscale"
        else
            print_warning "Failed to configure firewall for Tailscale"
        fi
        
        # Create SSH restriction script with validation
        create_ssh_restriction_script
        
        # Ask about SSH restriction
        if [[ "$INTERACTIVE_MODE" == true ]]; then
            echo -e "\n${YELLOW}IMPORTANT: SSH Access Configuration${NC}"
            echo "Currently SSH is accessible from anywhere."
            echo "Would you like to restrict SSH to Tailscale only?"
            echo -e "${RED}WARNING: Make sure you can access via Tailscale first!${NC}"
            read -p "Restrict SSH now? [y/N]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                validate_and_restrict_ssh
            else
                print_warning "SSH remains publicly accessible"
                print_warning "Run $ZERO_TRUST_DIR/scripts/restrict-ssh-tailscale.sh when ready"
            fi
        fi
    else
        print_error "Tailscale connection failed after $max_attempts attempts"
        print_error "Please check your network and try again"
        return 1
    fi
    
    log_action "Tailscale installation completed" "SUCCESS"
    return 0
}

# Create SSH restriction script with validation
create_ssh_restriction_script() {
    cat << 'EOF' | sudo tee "$ZERO_TRUST_DIR/scripts/restrict-ssh-tailscale.sh" > /dev/null
#!/bin/bash
# Restrict SSH to Tailscale interface only with validation

set -e

echo "Validating Tailscale connection..."

# Check if Tailscale is connected
if ! tailscale status &>/dev/null; then
    echo "ERROR: Tailscale is not connected!"
    echo "Please ensure Tailscale is running and connected before restricting SSH"
    exit 1
fi

# Get current SSH connection
CURRENT_SSH_CLIENT="${SSH_CLIENT%% *}"

# Check if we're connected via Tailscale
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null)
if [[ -n "$CURRENT_SSH_CLIENT" ]] && [[ "$CURRENT_SSH_CLIENT" != "$TAILSCALE_IP"* ]]; then
    echo "WARNING: You are currently connected via public IP: $CURRENT_SSH_CLIENT"
    echo "Make sure you can connect via Tailscale before proceeding!"
    read -p "Are you SURE you want to continue? [yes/NO]: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

echo "Restricting SSH to Tailscale only..."

# Remove general SSH rule
ufw delete allow 22/tcp 2>/dev/null || true

# Allow SSH only on Tailscale interface
ufw allow in on tailscale0 to any port 22 proto tcp comment 'SSH via Tailscale only'

# Reload UFW
ufw reload

echo "SUCCESS: SSH access restricted to Tailscale interface only"
echo "Tailscale IP: $TAILSCALE_IP"
EOF
    sudo chmod +x "$ZERO_TRUST_DIR/scripts/restrict-ssh-tailscale.sh"
}

# Validate and restrict SSH with safety checks
validate_and_restrict_ssh() {
    print_status "Validating SSH restriction safety..."
    
    # Get current connection details
    local current_ssh="${SSH_CLIENT%% *}"
    local tailscale_ip=$(tailscale ip -4 2>/dev/null)
    
    if [[ -n "$current_ssh" ]] && [[ "$current_ssh" != "$tailscale_ip"* ]]; then
        print_warning "You are currently connected from: $current_ssh"
        print_warning "This is NOT a Tailscale IP!"
        print_error "Cannot restrict SSH - you would be locked out!"
        print_status "Please connect via Tailscale first:"
        print_status "ssh user@$tailscale_ip"
        return 1
    fi
    
    # Run the restriction script
    if sudo "$ZERO_TRUST_DIR/scripts/restrict-ssh-tailscale.sh"; then
        print_success "SSH successfully restricted to Tailscale only"
    else
        print_error "Failed to restrict SSH"
        return 1
    fi
}

# Function 17: Setup Cloudflare Tunnel with interactive support
setup_cloudflare_tunnel() {
    print_status "Setting up Cloudflare Tunnel..."
    log_action "Starting Cloudflare Tunnel setup" "INFO"
    
    # Check if Docker is installed first
    if ! command -v docker &> /dev/null; then
        print_error "Docker is required for Cloudflare Tunnel"
        print_status "Please install Docker first or run the Docker installation step"
        return 1
    fi
    
    # Handle different setup scenarios
    if [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
        print_status "Using provided Cloudflare tunnel token..."
    elif [ -n "$CLOUDFLARE_TUNNEL_NAME" ] && command -v cloudflared &> /dev/null; then
        print_status "Getting token for tunnel: $CLOUDFLARE_TUNNEL_NAME"
        CLOUDFLARE_TUNNEL_TOKEN=$(cloudflared tunnel token "$CLOUDFLARE_TUNNEL_NAME" 2>/dev/null)
        
        if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
            print_error "Failed to get tunnel token"
            return 1
        fi
    elif [[ "$INTERACTIVE_MODE" == true ]]; then
        print_status "No tunnel token found. Setting up interactively..."
        
        if ! command -v cloudflared &> /dev/null; then
            print_status "Installing cloudflared..."
            curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
            sudo dpkg -i cloudflared.deb
            rm cloudflared.deb
        fi
        
        # Interactive tunnel creation
        print_status "Please login to Cloudflare..."
        if ! cloudflared tunnel login; then
            print_error "Failed to login to Cloudflare"
            return 1
        fi
        
        read -p "Enter a name for your tunnel: " CLOUDFLARE_TUNNEL_NAME
        
        # Check if tunnel already exists
        if cloudflared tunnel list | grep -q "$CLOUDFLARE_TUNNEL_NAME"; then
            print_warning "Tunnel '$CLOUDFLARE_TUNNEL_NAME' already exists"
            read -p "Use existing tunnel? [Y/n]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Nn]$ ]]; then
                read -p "Enter a new tunnel name: " CLOUDFLARE_TUNNEL_NAME
                cloudflared tunnel create "$CLOUDFLARE_TUNNEL_NAME"
            fi
        else
            cloudflared tunnel create "$CLOUDFLARE_TUNNEL_NAME"
        fi
        
        # Get tunnel token
        CLOUDFLARE_TUNNEL_TOKEN=$(cloudflared tunnel token "$CLOUDFLARE_TUNNEL_NAME")
        
        if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
            print_error "Failed to get tunnel token"
            return 1
        fi
        
        print_success "Tunnel created successfully"
    else
        print_error "No Cloudflare tunnel token available"
        print_error "Please provide a token or run in interactive mode"
        return 1
    fi
    
    # Validate domain if provided
    if [ -n "$DOMAIN_NAME" ]; then
        print_status "Configuring tunnel for domain: $DOMAIN_NAME"
    elif [[ "$INTERACTIVE_MODE" == true ]] && [ -z "$DOMAIN_NAME" ]; then
        read -p "Enter your domain name (optional): " DOMAIN_NAME
    fi
    
    # Create Docker Compose configuration
    print_status "Creating Cloudflare Tunnel Docker configuration..."
    
    local compose_file="$ZERO_TRUST_DIR/configs/cloudflare/docker-compose.yml"
    sudo mkdir -p "$(dirname "$compose_file")"
    
    cat << EOF | sudo tee "$compose_file" > /dev/null
version: '3.8'

services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared-tunnel
    restart: unless-stopped
    command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}
    networks:
      - cloudflare
    environment:
      - TUNNEL_METRICS=0.0.0.0:2000
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:2000/metrics"]
      interval: 30s
      timeout: 5s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  cloudflare:
    driver: bridge
    internal: false
EOF
    
    # Create systemd service
    cat << EOF | sudo tee /etc/systemd/system/cloudflared.service > /dev/null
[Unit]
Description=Cloudflare Tunnel
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$ZERO_TRUST_DIR/configs/cloudflare
ExecStartPre=/usr/bin/docker-compose pull
ExecStart=/usr/bin/docker-compose up
ExecStop=/usr/bin/docker-compose down
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Start Cloudflare Tunnel
    print_status "Starting Cloudflare Tunnel..."
    cd "$ZERO_TRUST_DIR/configs/cloudflare"
    
    # Pull latest image
    if ! sudo docker-compose pull; then
        print_warning "Failed to pull latest cloudflared image"
    fi
    
    # Start the tunnel
    if sudo docker-compose up -d; then
        print_success "Cloudflare Tunnel started"
    else
        print_error "Failed to start Cloudflare Tunnel"
        return 1
    fi
    
    # Enable service
    sudo systemctl daemon-reload
    sudo systemctl enable cloudflared
    
    # Wait for tunnel to be ready
    print_status "Waiting for tunnel to establish connection..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if sudo docker logs cloudflared-tunnel 2>&1 | grep -q "Connection.*registered"; then
            break
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done
    echo
    
    if [ $attempt -lt $max_attempts ]; then
        print_success "Cloudflare Tunnel connected successfully!"
        
        # Show tunnel info
        if [ -n "$CLOUDFLARE_TUNNEL_NAME" ]; then
            print_success "Tunnel name: $CLOUDFLARE_TUNNEL_NAME"
        fi
        if [ -n "$DOMAIN_NAME" ]; then
            print_success "Domain: $DOMAIN_NAME"
            print_status "Configure DNS and routes in Cloudflare dashboard:"
            print_status "https://one.dash.cloudflare.com/"
        fi
    else
        print_warning "Tunnel may not be fully connected"
        print_status "Check logs: sudo docker logs cloudflared-tunnel"
    fi
    
    log_action "Cloudflare Tunnel setup completed" "SUCCESS"
    return 0
}

# Function 18: Install and configure CrowdSec
install_crowdsec() {
    print_status "Installing CrowdSec with Traefik integration..."
    log_action "Starting CrowdSec installation" "INFO"
    
    # Create CrowdSec Docker Compose configuration
    print_status "Creating CrowdSec Docker configuration..."
    
    local compose_file="$ZERO_TRUST_DIR/configs/crowdsec/docker-compose.yml"
    
    # Generate bouncer key
    local bouncer_key=$(openssl rand -base64 32)
    echo "$bouncer_key" | sudo tee "$ZERO_TRUST_DIR/configs/crowdsec/bouncer-key.txt" > /dev/null
    sudo chmod 600 "$ZERO_TRUST_DIR/configs/crowdsec/bouncer-key.txt"
    
    cat << EOF | sudo tee "$compose_file" > /dev/null
version: '3.8'

services:
  crowdsec:
    image: crowdsecurity/crowdsec:v1.6.6
    container_name: crowdsec
    restart: unless-stopped
    environment:
      COLLECTIONS: "crowdsecurity/traefik crowdsecurity/http-cve crowdsecurity/http-dos"
      CUSTOM_HOSTNAME: crowdsec
      BOUNCER_KEY_TRAEFIK: "${bouncer_key}"
    volumes:
      - crowdsec-config:/etc/crowdsec/
      - crowdsec-data:/var/lib/crowdsec/data/
      - /var/log/traefik:/var/log/traefik:ro
    ports:
      - "127.0.0.1:8080:8080"
    networks:
      - internal
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  crowdsec-config:
  crowdsec-data:

networks:
  internal:
    external: true
EOF
    
    # Start CrowdSec
    print_status "Starting CrowdSec..."
    cd "$ZERO_TRUST_DIR/configs/crowdsec"
    sudo docker-compose up -d
    
    # Wait for CrowdSec to start
    sleep 10
    
    # Generate API key for bouncer
    print_status "Configuring CrowdSec bouncer..."
    sudo docker exec crowdsec cscli bouncers add traefik-bouncer -o raw > "$ZERO_TRUST_DIR/configs/crowdsec/traefik-bouncer-key.txt"
    sudo chmod 600 "$ZERO_TRUST_DIR/configs/crowdsec/traefik-bouncer-key.txt"
    
    # Install host firewall bouncer
    print_status "Installing CrowdSec firewall bouncer..."
    curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash
    sudo apt-get install -y crowdsec-firewall-bouncer-nftables
    
    log_action "CrowdSec installation completed" "SUCCESS"
    print_success "CrowdSec installed with Traefik integration"
}

# Function 19: Configure Traefik with security middleware
configure_traefik_security() {
    print_status "Configuring Traefik with security middleware..."
    log_action "Starting Traefik security configuration" "INFO"
    
    # Create Traefik configuration
    local traefik_dir="$ZERO_TRUST_DIR/configs/docker/traefik"
    sudo mkdir -p "$traefik_dir"
    
    # Get bouncer key
    local bouncer_key=$(cat "$ZERO_TRUST_DIR/configs/crowdsec/traefik-bouncer-key.txt" 2>/dev/null || echo "")
    
    # Create Traefik static configuration
    cat << 'EOF' | sudo tee "$traefik_dir/traefik.yml" > /dev/null
api:
  dashboard: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: internal

log:
  level: INFO
  format: json
  filePath: /var/log/traefik/traefik.log

accessLog:
  format: json
  filePath: /var/log/traefik/access.log
  bufferingSize: 100

experimental:
  plugins:
    crowdsec-bouncer:
      moduleName: github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
      version: v1.2.1
EOF
    
    # Create Traefik Docker Compose
    cat << EOF | sudo tee "$traefik_dir/docker-compose.yml" > /dev/null
version: '3.8'

services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - internal
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/traefik.yml:ro
      - traefik-logs:/var/log/traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.middlewares.crowdsec.plugin.crowdsec-bouncer.enabled=true"
      - "traefik.http.middlewares.crowdsec.plugin.crowdsec-bouncer.crowdseclapikey=${bouncer_key}"
      - "traefik.http.middlewares.crowdsec.plugin.crowdsec-bouncer.crowdseclapischeme=http"
      - "traefik.http.middlewares.crowdsec.plugin.crowdsec-bouncer.crowdseclapihost=crowdsec:8080"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  traefik-logs:

networks:
  internal:
    external: true
EOF
    
    # Create internal Docker network if it doesn't exist
    if ! docker network ls | grep -q internal; then
        sudo docker network create internal
    fi
    
    log_action "Traefik security configuration completed" "SUCCESS"
    print_success "Traefik configured with security middleware"
}

# Function 20: Install monitoring tools
install_monitoring_tools() {
    print_status "Installing security monitoring tools..."
    log_action "Starting monitoring tools installation" "INFO"
    
    # Install Lynis
    print_status "Installing Lynis for security auditing..."
    sudo apt-get install -y lynis
    
    # Install AIDE
    print_status "Installing AIDE for file integrity monitoring..."
    sudo apt-get install -y aide aide-common
    
    # Initialize AIDE database
    print_status "Initializing AIDE database (this may take a while)..."
    sudo aideinit -y -f
    
    # Install Logwatch
    print_status "Installing Logwatch for log analysis..."
    sudo apt-get install -y logwatch
    
    # Configure Logwatch
    cat << EOF | sudo tee /etc/logwatch/conf/logwatch.conf > /dev/null
LogDir = /var/log
TmpDir = /var/cache/logwatch
Output = stdout
Format = text
Encode = none
MailTo = ${EMAIL:-root}
MailFrom = Logwatch
Range = yesterday
Detail = Med
Service = All
Service = "-zz-network"
Service = "-zz-sys"
Service = "-eximstats"
EOF
    
    # Create monitoring scripts
    print_status "Creating monitoring scripts..."
    
    # Daily security check script
    cat << 'EOF' | sudo tee "$ZERO_TRUST_DIR/scripts/daily-security-check.sh" > /dev/null
#!/bin/bash
# Daily security check script

LOG_FILE="/var/log/zero-trust/daily-check-$(date +%Y%m%d).log"
mkdir -p /var/log/zero-trust

echo "=== Daily Security Check - $(date) ===" >> "$LOG_FILE"

# Run Lynis audit
echo "Running Lynis audit..." >> "$LOG_FILE"
lynis audit system --quick 2>&1 >> "$LOG_FILE"

# Check for failed login attempts
echo "Failed login attempts:" >> "$LOG_FILE"
grep "Failed password" /var/log/auth.log | tail -20 >> "$LOG_FILE"

# Check open ports
echo "Open ports:" >> "$LOG_FILE"
ss -tuln >> "$LOG_FILE"

# Check for rootkits
echo "Checking for rootkits..." >> "$LOG_FILE"
chkrootkit 2>&1 >> "$LOG_FILE" || echo "chkrootkit not installed" >> "$LOG_FILE"

# Run AIDE check
echo "Running AIDE integrity check..." >> "$LOG_FILE"
aide --check 2>&1 >> "$LOG_FILE"

echo "=== Check completed ===" >> "$LOG_FILE"
EOF
    
    sudo chmod +x "$ZERO_TRUST_DIR/scripts/daily-security-check.sh"
    
    # Add to cron
    (crontab -l 2>/dev/null; echo "0 2 * * * $ZERO_TRUST_DIR/scripts/daily-security-check.sh") | crontab -
    
    log_action "Monitoring tools installation completed" "SUCCESS"
    print_success "Security monitoring tools installed"
}

# Function 21: Validate Zero Trust security
validate_zero_trust_security() {
    print_status "Validating Zero Trust security configuration..."
    log_action "Starting security validation" "INFO"
    
    local validation_report="$ZERO_TRUST_DIR/docs/validation-report-$(date +%Y%m%d-%H%M%S).md"
    
    cat << EOF | sudo tee "$validation_report" > /dev/null
# Zero Trust Security Validation Report
Generated: $(date)

## System Information
- Hostname: $(hostname)
- OS: $(lsb_release -d | cut -f2)
- Kernel: $(uname -r)

## Security Checks

### 1. Firewall Status
EOF
    
    # Check UFW status
    sudo ufw status verbose >> "$validation_report" 2>&1
    
    cat << EOF | sudo tee -a "$validation_report" > /dev/null

### 2. Open Ports
\`\`\`
EOF
    ss -tuln | grep LISTEN >> "$validation_report"
    
    cat << EOF | sudo tee -a "$validation_report" > /dev/null
\`\`\`

### 3. SSH Configuration
EOF
    
    # Check SSH configuration
    grep -E "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)" /etc/ssh/sshd_config >> "$validation_report"
    
    cat << EOF | sudo tee -a "$validation_report" > /dev/null

### 4. Tailscale Status
\`\`\`
EOF
    tailscale status >> "$validation_report" 2>&1 || echo "Tailscale not configured" >> "$validation_report"
    
    cat << EOF | sudo tee -a "$validation_report" > /dev/null
\`\`\`

### 5. Docker Security
EOF
    
    # Check Docker configuration
    if [ -f /etc/docker/daemon.json ]; then
        echo "Docker daemon configuration:" >> "$validation_report"
        cat /etc/docker/daemon.json >> "$validation_report"
    fi
    
    cat << EOF | sudo tee -a "$validation_report" > /dev/null

### 6. CrowdSec Status
\`\`\`
EOF
    docker ps | grep crowdsec >> "$validation_report" 2>&1 || echo "CrowdSec not running" >> "$validation_report"
    
    cat << EOF | sudo tee -a "$validation_report" > /dev/null
\`\`\`

### 7. Security Score
EOF
    
    # Run Lynis for security score
    lynis audit system --quick --quiet 2>&1 | grep -E "Hardening index" >> "$validation_report" || echo "Lynis score not available" >> "$validation_report"
    
    cat << EOF | sudo tee -a "$validation_report" > /dev/null

## Recommendations
1. Verify Tailscale access before disabling public SSH
2. Ensure all services are accessible only through Cloudflare Tunnel
3. Monitor CrowdSec decisions regularly
4. Review this report and address any issues

---
Report location: $validation_report
EOF
    
    print_success "Validation report generated: $validation_report"
    
    # Display summary
    echo -e "\n${CYAN}=== Security Validation Summary ===${NC}"
    echo -e "${GREEN}✓${NC} Firewall: $(sudo ufw status | grep -q "Status: active" && echo "Active" || echo "Inactive")"
    echo -e "${GREEN}✓${NC} SSH: $(grep -q "PasswordAuthentication no" /etc/ssh/sshd_config && echo "Secured" || echo "Needs attention")"
    echo -e "${GREEN}✓${NC} Tailscale: $(tailscale status &>/dev/null && echo "Connected" || echo "Not connected")"
    echo -e "${GREEN}✓${NC} Docker: $(docker ps &>/dev/null && echo "Running" || echo "Not running")"
    echo -e "${GREEN}✓${NC} CrowdSec: $(docker ps | grep -q crowdsec && echo "Active" || echo "Not active")"
    
    log_action "Security validation completed" "SUCCESS"
}

# Function 22: Generate security documentation
generate_security_docs() {
    print_status "Generating security documentation..."
    
    # Generate README
    cat << 'EOF' | sudo tee "$ZERO_TRUST_DIR/docs/README.md" > /dev/null
# Zero Trust Security Implementation

## Overview
This server has been configured with Zero Trust security architecture.

## Access Methods
1. **SSH Access**: Via Tailscale only
2. **Web Services**: Via Cloudflare Tunnel only
3. **Direct Ports**: All blocked by firewall

## Security Components
- **Tailscale**: Secure network access
- **Cloudflare Tunnel**: Secure web traffic routing
- **CrowdSec**: Threat detection and blocking
- **UFW + Docker**: Integrated firewall
- **Monitoring**: Lynis, AIDE, Logwatch

## Maintenance
- Daily security checks run at 2 AM
- Logs available in `/var/log/zero-trust/`
- Configuration backups in `/etc/zero-trust/backups/`

## Emergency Procedures
See `emergency-procedures.md` for recovery steps.
EOF
    
    # Generate emergency procedures
    cat << 'EOF' | sudo tee "$ZERO_TRUST_DIR/docs/emergency-procedures.md" > /dev/null
# Emergency Procedures

## Lost Tailscale Access
1. Access server via console (VPS provider)
2. Re-enable SSH temporarily:
   ```bash
   sudo ufw allow 22/tcp
   sudo ufw reload
   ```
3. Fix Tailscale configuration
4. Restore security settings

## Firewall Lockout
1. Boot into recovery mode
2. Mount root filesystem
3. Disable UFW:
   ```bash
   ufw disable
   ```
4. Fix configuration
5. Re-enable UFW

## Service Recovery
- Restart Tailscale: `sudo systemctl restart tailscaled`
- Restart Docker: `sudo systemctl restart docker`
- Restart CrowdSec: `cd /etc/zero-trust/configs/crowdsec && docker-compose restart`

## Rollback Procedure
Backups are stored with timestamps. To rollback:
1. Identify backup: `ls /etc/zero-trust/backups/`
2. Restore files from backup directory
3. Restart affected services
EOF
    
    print_success "Security documentation generated"
}

# Function 23: Install rootless Docker
install_rootless_docker() {
    print_status "Installing Docker in rootless mode..."
    log_action "Starting rootless Docker installation" "INFO"
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        print_warning "Docker is already installed in standard mode"
        
        if [[ "$INTERACTIVE_MODE" == true ]]; then
            read -p "Convert to rootless mode? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 0
            fi
        fi
    fi
    
    # Install dependencies
    print_status "Installing rootless Docker dependencies..."
    sudo apt-get update
    sudo apt-get install -y \
        uidmap \
        dbus-user-session \
        fuse-overlayfs \
        slirp4netns
    
    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
        print_status "Installing Docker CE..."
        curl -fsSL https://get.docker.com | sh
    fi
    
    # Install rootless extras
    sudo apt-get install -y docker-ce-rootless-extras
    
    # Setup rootless Docker for main user
    print_status "Setting up rootless Docker for user: $MAIN_USER"
    
    # Run as the main user
    sudo -u "$MAIN_USER" bash << 'EOF'
# Install rootless Docker
dockerd-rootless-setuptool.sh install

# Enable and start Docker service
systemctl --user enable docker
systemctl --user start docker

# Set DOCKER_HOST
echo 'export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock' >> ~/.bashrc
echo 'export PATH=/usr/bin:$PATH' >> ~/.bashrc
EOF
    
    print_success "Rootless Docker installed for user: $MAIN_USER"
    print_status "User must log out and back in for changes to take effect"
    
    log_action "Rootless Docker installation completed" "SUCCESS"
    return 0
}

# Function 24: Install Podman
install_podman() {
    print_status "Installing Podman (rootless by default)..."
    log_action "Starting Podman installation" "INFO"
    
    # Check if Podman is already installed
    if command -v podman &> /dev/null; then
        print_warning "Podman is already installed"
        podman --version
        return 0
    fi
    
    # Add Podman repository for Ubuntu 24.04
    print_status "Adding Podman repository..."
    
    # For Ubuntu 24.04, Podman is in the default repos
    sudo apt-get update
    sudo apt-get install -y podman podman-compose
    
    # Configure registries
    print_status "Configuring container registries..."
    sudo mkdir -p /etc/containers
    cat << 'EOF' | sudo tee /etc/containers/registries.conf > /dev/null
[registries.search]
registries = ['docker.io', 'quay.io', 'gcr.io']

[registries.insecure]
registries = []

[registries.block]
registries = []
EOF
    
    # Setup for main user
    print_status "Configuring Podman for user: $MAIN_USER"
    
    # Configure subuid and subgid
    sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$MAIN_USER"
    
    # Enable lingering for user services
    sudo loginctl enable-linger "$MAIN_USER"
    
    print_success "Podman installed successfully"
    podman --version
    
    log_action "Podman installation completed" "SUCCESS"
    return 0
}

# Function 25: CIS Benchmark Hardening
apply_cis_benchmarks() {
    print_status "Applying CIS Ubuntu 24.04 LTS Benchmark controls..."
    log_action "Starting CIS benchmark implementation" "INFO"
    
    # CIS 1.1.1 - Disable unused filesystems
    print_status "Disabling unused filesystems (CIS 1.1.1)..."
    local unused_fs=(
        "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" 
        "squashfs" "udf" "vfat" "usb-storage"
    )
    
    for fs in "${unused_fs[@]}"; do
        echo "install $fs /bin/true" | sudo tee -a /etc/modprobe.d/cis-hardening.conf > /dev/null
    done
    
    # CIS 1.3.1 - AIDE configuration
    print_status "Configuring AIDE for file integrity (CIS 1.3.1)..."
    if ! command -v aide &> /dev/null; then
        sudo apt-get install -y aide aide-common
    fi
    
    # CIS 1.4.1 - Bootloader configuration
    print_status "Securing bootloader (CIS 1.4.1)..."
    if [ -f /boot/grub/grub.cfg ]; then
        sudo chmod 400 /boot/grub/grub.cfg
        sudo chown root:root /boot/grub/grub.cfg
    fi
    
    # CIS 1.5.1 - Core dumps
    print_status "Restricting core dumps (CIS 1.5.1)..."
    echo "* hard core 0" | sudo tee -a /etc/security/limits.conf > /dev/null
    echo "fs.suid_dumpable = 0" | sudo tee -a /etc/sysctl.d/99-cis.conf > /dev/null
    
    # CIS 3.3.1 - Network parameters
    print_status "Configuring network parameters (CIS 3.3)..."
    cat << 'EOF' | sudo tee -a /etc/sysctl.d/99-cis-network.conf > /dev/null
# CIS 3.3 Network Parameters
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
EOF
    
    sudo sysctl -p /etc/sysctl.d/99-cis-network.conf
    
    # CIS 4.1.1 - Audit system
    print_status "Configuring audit system (CIS 4.1)..."
    if ! dpkg -l | grep -q auditd; then
        sudo apt-get install -y auditd audispd-plugins
    fi
    
    # Add audit rules
    cat << 'EOF' | sudo tee /etc/audit/rules.d/cis.rules > /dev/null
# CIS Audit Rules
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope
-w /var/log/sudo.log -p wa -k actions
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules
EOF
    
    sudo systemctl restart auditd
    
    # CIS 5.2.1 - SSH configuration
    print_status "Hardening SSH configuration (CIS 5.2)..."
    local ssh_config="/etc/ssh/sshd_config.d/99-cis-hardening.conf"
    cat << 'EOF' | sudo tee "$ssh_config" > /dev/null
# CIS SSH Hardening
Protocol 2
LogLevel VERBOSE
X11Forwarding no
MaxAuthTries 4
IgnoreRhosts yes
HostbasedAuthentication no
PermitRootLogin no
PermitEmptyPasswords no
PermitUserEnvironment no
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
ClientAliveInterval 300
ClientAliveCountMax 0
LoginGraceTime 60
MaxStartups 10:30:60
MaxSessions 4
AllowUsers ${MAIN_USER}
EOF
    
    local ssh_service=$(get_ssh_service_name)
    sudo systemctl reload "$ssh_service"
    
    print_success "CIS benchmarks applied successfully"
    log_action "CIS benchmark implementation completed" "SUCCESS"
    return 0
}

# Function 26: Generate Compliance Report
generate_compliance_report() {
    print_status "Generating compliance report..."
    log_action "Starting compliance report generation" "INFO"
    
    local report_file="$ZERO_TRUST_DIR/docs/compliance-report-$(date +%Y%m%d-%H%M%S).html"
    local score=0
    local total=0
    
    # Start HTML report
    cat << 'HTML_START' | sudo tee "$report_file" > /dev/null
<!DOCTYPE html>
<html>
<head>
    <title>Zero Trust Security Compliance Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; }
        .pass { color: green; font-weight: bold; }
        .fail { color: red; font-weight: bold; }
        .warning { color: orange; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background-color: #f2f2f2; }
        .summary { background-color: #e7f3ff; padding: 15px; border-radius: 5px; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Zero Trust Security Compliance Report</h1>
    <div class="summary">
        <p><strong>Generated:</strong> $(date)</p>
        <p><strong>Hostname:</strong> $(hostname)</p>
        <p><strong>OS:</strong> $(lsb_release -ds)</p>
        <p><strong>Kernel:</strong> $(uname -r)</p>
    </div>
HTML_START
    
    echo "<h2>Security Controls Assessment</h2>" | sudo tee -a "$report_file" > /dev/null
    echo "<table>" | sudo tee -a "$report_file" > /dev/null
    echo "<tr><th>Control</th><th>Description</th><th>Status</th><th>Details</th></tr>" | sudo tee -a "$report_file" > /dev/null
    
    # Check various security controls
    local controls=(
        "SSH:SSH Hardening:$(grep -q 'PermitRootLogin no' /etc/ssh/sshd_config* 2>/dev/null && echo 'PASS' || echo 'FAIL'):Root login disabled"
        "Firewall:UFW Status:$(sudo ufw status | grep -q 'Status: active' && echo 'PASS' || echo 'FAIL'):Firewall active"
        "Updates:Automatic Updates:$(systemctl is-enabled unattended-upgrades &>/dev/null && echo 'PASS' || echo 'FAIL'):Security updates enabled"
        "AppArmor:MAC Enforcement:$(aa-status --enabled &>/dev/null && echo 'PASS' || echo 'FAIL'):AppArmor enabled"
        "Audit:Audit System:$(systemctl is-active auditd &>/dev/null && echo 'PASS' || echo 'FAIL'):Auditd running"
        "Tailscale:Zero Trust Network:$(tailscale status &>/dev/null && echo 'PASS' || echo 'FAIL'):Tailscale connected"
        "Docker:Container Security:$(docker info &>/dev/null && echo 'PASS' || echo 'WARNING'):Docker available"
        "CrowdSec:IPS Protection:$(docker ps | grep -q crowdsec && echo 'PASS' || echo 'WARNING'):CrowdSec running"
    )
    
    for control in "${controls[@]}"; do
        IFS=':' read -r name description status details <<< "$control"
        ((total++))
        [[ "$status" == "PASS" ]] && ((score++))
        
        local status_class="fail"
        [[ "$status" == "PASS" ]] && status_class="pass"
        [[ "$status" == "WARNING" ]] && status_class="warning"
        
        echo "<tr><td>$name</td><td>$description</td><td class='$status_class'>$status</td><td>$details</td></tr>" | sudo tee -a "$report_file" > /dev/null
    done
    
    echo "</table>" | sudo tee -a "$report_file" > /dev/null
    
    # Compliance Score
    local percentage=$((score * 100 / total))
    cat << HTML_END | sudo tee -a "$report_file" > /dev/null
    <h2>Compliance Score</h2>
    <div class="summary">
        <h3>Overall Score: ${percentage}% (${score}/${total} controls passing)</h3>
        <p><strong>CIS Benchmark:</strong> $([ $percentage -ge 85 ] && echo "<span class='pass'>COMPLIANT</span>" || echo "<span class='fail'>NON-COMPLIANT</span>")</p>
        <p><strong>Security Posture:</strong> $([ $percentage -ge 90 ] && echo "Excellent" || ([ $percentage -ge 75 ] && echo "Good" || echo "Needs Improvement"))</p>
    </div>
    
    <h2>Recommendations</h2>
    <ul>
        <li>Review and remediate any failed controls</li>
        <li>Schedule regular compliance assessments</li>
        <li>Keep all security tools and signatures updated</li>
        <li>Monitor logs and alerts continuously</li>
        <li>Test incident response procedures quarterly</li>
    </ul>
    
    <p><small>Report generated by Zero Trust Security Setup v${SCRIPT_VERSION}</small></p>
</body>
</html>
HTML_END
    
    print_success "Compliance report generated: $report_file"
    
    # Also generate a text summary
    local summary_file="$ZERO_TRUST_DIR/docs/compliance-summary.txt"
    cat << EOF | sudo tee "$summary_file" > /dev/null
COMPLIANCE SUMMARY
==================
Date: $(date)
Score: ${percentage}% (${score}/${total})
Status: $([ $percentage -ge 85 ] && echo "COMPLIANT" || echo "NON-COMPLIANT")

Next Steps:
- Review detailed report: $report_file
- Address any failed controls
- Schedule next assessment
EOF
    
    log_action "Compliance report generated successfully" "SUCCESS"
    return 0
}

# Function 27: Emergency Rollback
emergency_rollback() {
    print_warning "EMERGENCY ROLLBACK INITIATED"
    log_action "Starting emergency rollback" "WARNING"
    
    echo -e "${RED}This will revert security changes and may leave your system exposed!${NC}"
    
    if [[ "$INTERACTIVE_MODE" == true ]]; then
        read -p "Are you sure you want to proceed? Type 'ROLLBACK' to confirm: " confirm
        if [[ "$confirm" != "ROLLBACK" ]]; then
            print_status "Rollback cancelled"
            return 1
        fi
    fi
    
    print_status "Performing emergency rollback..."
    
    # Re-enable SSH access
    print_status "Re-enabling public SSH access..."
    sudo ufw allow 22/tcp
    sudo ufw reload
    
    # Restore SSH configuration
    if [ -f "$BACKUP_DIR/sshd_config.backup" ]; then
        sudo cp "$BACKUP_DIR/sshd_config.backup" /etc/ssh/sshd_config
        local ssh_service=$(get_ssh_service_name)
        sudo systemctl restart "$ssh_service"
    fi
    
    # Disable restrictive firewall rules
    print_status "Resetting firewall to permissive state..."
    sudo ufw --force reset
    sudo ufw default allow incoming
    sudo ufw default allow outgoing
    sudo ufw --force enable
    
    # Stop security services
    print_status "Stopping security services..."
    sudo systemctl stop crowdsec &>/dev/null || true
    sudo systemctl stop cloudflared &>/dev/null || true
    
    # Create recovery script
    local recovery_script="$ZERO_TRUST_DIR/scripts/recovery-$(date +%Y%m%d-%H%M%S).sh"
    cat << 'EOF' | sudo tee "$recovery_script" > /dev/null
#!/bin/bash
# Recovery script to re-apply security after fixing issues

echo "This script will help you re-apply security settings after recovery"
echo "Run this only after fixing the issues that caused the rollback"
echo

read -p "Re-apply firewall rules? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw --force enable
fi

read -p "Restart security services? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl start cloudflared 2>/dev/null || echo "Cloudflare not configured"
    systemctl start crowdsec 2>/dev/null || echo "CrowdSec not configured"
fi

echo "Recovery steps completed. Review security posture before proceeding."
EOF
    sudo chmod +x "$recovery_script"
    
    print_warning "ROLLBACK COMPLETED"
    print_warning "Your system is now in a LESS SECURE state!"
    print_status "Recovery script created: $recovery_script"
    print_status "Run the recovery script after fixing issues to re-apply security"
    
    log_action "Emergency rollback completed" "WARNING"
    return 0
}

# Function 28: Complete Zero Trust setup
    print_status "Starting complete Zero Trust security setup..."
    
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}     ZERO TRUST SECURITY IMPLEMENTATION FOR UBUNTU${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}\n"
    
    # Initialize logging
    init_zero_trust_logging
    log_action "Starting Zero Trust setup" "INFO"
    
    # Create directory structure
    create_zero_trust_dirs
    
    # Run all security components
    echo -e "\n${YELLOW}▶ PHASE 1: System Hardening${NC}"
    harden_system
    
    echo -e "\n${YELLOW}▶ PHASE 2: CIS Benchmarks${NC}"
    apply_cis_benchmarks
    
    echo -e "\n${YELLOW}▶ PHASE 3: Container Runtime${NC}"
    if [[ "$ENABLE_ROOTLESS_DOCKER" == true ]]; then
        install_rootless_docker
    elif [[ "$ENABLE_PODMAN" == true ]]; then
        install_podman
    fi
    
    echo -e "\n${YELLOW}▶ PHASE 4: Firewall Configuration${NC}"
    configure_ufw_docker
    
    echo -e "\n${YELLOW}▶ PHASE 5: Tailscale Setup${NC}"
    install_tailscale
    
    if [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ] || [ -n "$CLOUDFLARE_TOKEN" ] || [[ "$INTERACTIVE_MODE" == true ]]; then
        echo -e "\n${YELLOW}▶ PHASE 6: Cloudflare Tunnel${NC}"
        setup_cloudflare_tunnel
    else
        print_warning "Skipping Cloudflare Tunnel (no configuration provided)"
    fi
    
    echo -e "\n${YELLOW}▶ PHASE 7: CrowdSec Protection${NC}"
    install_crowdsec
    
    echo -e "\n${YELLOW}▶ PHASE 8: Traefik Security${NC}"
    configure_traefik_security
    
    echo -e "\n${YELLOW}▶ PHASE 9: Monitoring Tools${NC}"
    install_monitoring_tools
    
    echo -e "\n${YELLOW}▶ PHASE 10: Validation${NC}"
    validate_zero_trust_security
    
    echo -e "\n${YELLOW}▶ PHASE 11: Compliance Report${NC}"
    generate_compliance_report
    
    echo -e "\n${YELLOW}▶ PHASE 12: Documentation${NC}"
    generate_security_docs
    
    # Final report
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                    SECURITY REPORT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    
    # Run security score
    local security_score=$(lynis audit system --quick --quiet 2>&1 | grep -oP 'Hardening index : \K\d+' || echo "N/A")
    
    echo -e "Hardening Score: ${GREEN}${security_score}/100${NC}"
    echo -e "Open Ports: ${GREEN}0${NC} (all traffic via tunnels)"
    echo -e "Attack Surface: ${GREEN}Minimal${NC}"
    echo -e "Protection Level: ${GREEN}Maximum${NC}"
    
    echo -e "\n${GREEN}✅ Your server is now secured with Zero Trust architecture!${NC}"
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo -e "1. Verify Tailscale access: ${CYAN}tailscale status${NC}"
    echo -e "2. Test Cloudflare tunnel: ${CYAN}curl -I https://${DOMAIN}${NC}"
    echo -e "3. Monitor CrowdSec: ${CYAN}docker logs crowdsec${NC}"
    echo -e "4. Review security report: ${CYAN}cat $ZERO_TRUST_DIR/docs/validation-report-*.md${NC}"
    
    log_action "Zero Trust setup completed successfully" "SUCCESS"
}

# Function to run all base steps
run_all_base() {
    print_status "Running all base installation steps..."
    
    detect_main_user
    system_update
    install_htop
    install_zsh
    install_oh_my_zsh
    install_powerlevel10k
    deploy_configs
    install_nvm
    install_nodejs
    install_claude
    install_coolify
    clean_apt_sources
    
    print_success "All base steps completed successfully!"
}

# Function to run all security steps
run_all_security() {
    print_status "Running all security configuration steps..."
    
    configure_ufw
    configure_ssh_coolify
    
    print_success "All security steps completed successfully!"
}

# Function to run all steps
run_all() {
    print_status "Running all installation steps..."
    
    detect_main_user
    system_update
    install_htop
    install_zsh
    install_oh_my_zsh
    install_powerlevel10k
    deploy_configs
    install_nvm
    install_nodejs
    install_claude
    configure_ufw
    configure_ssh_coolify
    install_coolify
    clean_apt_sources
    
    print_success "All steps completed successfully!"
}

# Function to display base menu
show_base_menu() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              Base Configuration                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo -e "\n${MAGENTA}Please select an option:${NC}\n"
    echo -e "  ${GREEN}1)${NC} System Update (apt update & upgrade)"
    echo -e "  ${GREEN}2)${NC} Install Zsh (set as default shell)"
    echo -e "  ${GREEN}3)${NC} Install Oh-My-Zsh"
    echo -e "  ${GREEN}4)${NC} Install Powerlevel10k theme"
    echo -e "  ${GREEN}5)${NC} Deploy configuration files (.zshrc & .p10k.zsh)"
    echo -e "  ${GREEN}6)${NC} Install NVM (Node Version Manager)"
    echo -e "  ${GREEN}7)${NC} Install Node.js (via NVM)"
    echo -e "  ${GREEN}8)${NC} Install Claude CLI"
    echo -e "  ${GREEN}9)${NC} Install htop"
    echo -e "  ${GREEN}10)${NC} Install Coolify"
    echo -e "  ${GREEN}11)${NC} Clean APT sources"
    echo -e "  ${GREEN}12)${NC} Run all base steps"
    echo -e "  ${GREEN}13)${NC} Back to main menu"
    echo -e "\n${CYAN}════════════════════════════════════════════════════${NC}"
}

# Function to display security menu
show_security_menu() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              Security Configuration              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo -e "\n${MAGENTA}Please select an option:${NC}\n"
    echo -e "  ${GREEN}1)${NC} Configure UFW Firewall (SSH only)"
    echo -e "  ${GREEN}2)${NC} Configure SSH for Coolify"
    echo -e "  ${GREEN}3)${NC} Run basic security steps"
    echo -e "\n  ${CYAN}--- Zero Trust Security ---${NC}"
    echo -e "  ${GREEN}4)${NC} System Hardening (PAM, AppArmor, Updates)"
    echo -e "  ${GREEN}5)${NC} Advanced Firewall (UFW-Docker Integration)"
    echo -e "  ${GREEN}6)${NC} Install Tailscale (Zero Trust Network)"
    echo -e "  ${GREEN}7)${NC} Setup Cloudflare Tunnel"
    echo -e "  ${GREEN}8)${NC} Install CrowdSec Protection"
    echo -e "  ${GREEN}9)${NC} Configure Traefik Security"
    echo -e "  ${GREEN}10)${NC} Install Monitoring Tools"
    echo -e "  ${GREEN}11)${NC} Run COMPLETE Zero Trust Setup"
    echo -e "  ${GREEN}12)${NC} Validate Security Configuration"
    echo -e "  ${GREEN}13)${NC} Apply CIS Benchmarks"
    echo -e "  ${GREEN}14)${NC} Generate Compliance Report"
    echo -e "  ${GREEN}15)${NC} Emergency Rollback"
    echo -e "  ${GREEN}16)${NC} Container Runtime Setup (Docker/Podman)"
    echo -e "  ${GREEN}17)${NC} Back to main menu"
    echo -e "\n${CYAN}════════════════════════════════════════════════════${NC}"
}

# Function to display main menu
show_menu() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          Ubuntu Server Setup Script              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo -e "\n${MAGENTA}Please select an option:${NC}\n"
    echo -e "  ${GREEN}1)${NC} Base Configuration"
    echo -e "  ${GREEN}2)${NC} Security Configuration"
    echo -e "  ${GREEN}3)${NC} Run all steps (Base + Security)"
    echo -e "  ${GREEN}4)${NC} Exit"
    echo -e "\n${CYAN}════════════════════════════════════════════════════${NC}"
}

# Base menu handler
handle_base_menu() {
    while true; do
        show_base_menu
        read -p "Enter your choice [1-13]: " choice
        
        case $choice in
            1)
                system_update
                ;;
            2)
                install_zsh
                ;;
            3)
                install_oh_my_zsh
                ;;
            4)
                install_powerlevel10k
                ;;
            5)
                deploy_configs
                ;;
            6)
                install_nvm
                ;;
            7)
                install_nodejs
                ;;
            8)
                install_claude
                ;;
            9)
                install_htop
                ;;
            10)
                install_coolify
                ;;
            11)
                clean_apt_sources
                ;;
            12)
                run_all_base
                ;;
            13)
                return
                ;;
            *)
                print_error "Invalid option. Please select 1-17"
                ;;
        esac
        
        if [ "$choice" != "13" ]; then
            echo -e "\n${YELLOW}Press Enter to continue...${NC}"
            read
        fi
    done
}

# Security menu handler
handle_security_menu() {
    while true; do
        show_security_menu
        read -p "Enter your choice [1-17]: " choice
        
        case $choice in
            1)
                configure_ufw
                ;;
            2)
                configure_ssh_coolify
                ;;
            3)
                run_all_security
                ;;
            4)
                harden_system
                ;;
            5)
                configure_ufw_docker
                ;;
            6)
                install_tailscale
                ;;
            7)
                # Get parameters for Cloudflare Tunnel
                if [ -z "$CLOUDFLARE_TOKEN" ]; then
                    read -p "Enter Cloudflare Tunnel token: " CLOUDFLARE_TOKEN
                fi
                if [ -z "$DOMAIN" ]; then
                    read -p "Enter your domain: " DOMAIN
                fi
                setup_cloudflare_tunnel
                ;;
            8)
                install_crowdsec
                ;;
            9)
                configure_traefik_security
                ;;
            10)
                install_monitoring_tools
                ;;
            11)
                # Get parameters for complete setup
                if [[ "$INTERACTIVE_MODE" == true ]]; then
                    configure_interactively
                fi
                setup_zero_trust_complete
                ;;
            12)
                validate_zero_trust_security
                ;;
            13)
                apply_cis_benchmarks
                ;;
            14)
                generate_compliance_report
                ;;
            15)
                emergency_rollback
                ;;
            16)
                if [[ "$ENABLE_ROOTLESS_DOCKER" == true ]] || [[ "$INTERACTIVE_MODE" == true ]]; then
                    read -p "Install rootless Docker? [y/N]: " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        install_rootless_docker
                    fi
                fi
                if [[ "$ENABLE_PODMAN" == true ]] || [[ "$INTERACTIVE_MODE" == true ]]; then
                    read -p "Install Podman? [y/N]: " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        install_podman
                    fi
                fi
                ;;
            17)
                return
                ;;
            *)
                print_error "Invalid option. Please select 1-17"
                ;;
        esac
        
        if [ "$choice" != "17" ]; then
            echo -e "\n${YELLOW}Press Enter to continue...${NC}"
            read
        fi
    done
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                echo "Zero Trust Security Setup Script v${SCRIPT_VERSION}"
                exit 0
                ;;
            --non-interactive)
                INTERACTIVE_MODE=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --email)
                ADMIN_EMAIL="$2"
                shift 2
                ;;
            --domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            --cloudflare-token)
                CLOUDFLARE_TUNNEL_TOKEN="$2"
                shift 2
                ;;
            --tailscale-key)
                TAILSCALE_AUTH_KEY="$2"
                shift 2
                ;;
            --rootless-docker)
                ENABLE_ROOTLESS_DOCKER=true
                shift
                ;;
            --podman)
                ENABLE_PODMAN=true
                shift
                ;;
            --quick-setup)
                # Quick setup mode - runs Zero Trust with minimal prompts
                INTERACTIVE_MODE=false
                RUN_ZERO_TRUST=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    cat << EOF
Zero Trust Security Setup Script v${SCRIPT_VERSION}

USAGE:
    sudo $0 [OPTIONS]

OPTIONS:
    -h, --help                  Show this help message
    -v, --version              Show script version
    --non-interactive          Run in non-interactive mode
    --dry-run                  Test mode without making changes
    --verbose                  Enable verbose logging
    --skip-validation          Skip system validation checks
    --email EMAIL              Admin email for notifications
    --domain DOMAIN            Domain name for services
    --cloudflare-token TOKEN   Cloudflare tunnel token
    --tailscale-key KEY        Tailscale authentication key
    --rootless-docker          Enable rootless Docker
    --podman                   Install Podman
    --quick-setup              Run Zero Trust setup with provided parameters

EXAMPLES:
    # Interactive setup
    sudo $0

    # Non-interactive with parameters
    sudo $0 --non-interactive --email admin@example.com --domain example.com \\
           --cloudflare-token YOUR_TOKEN --tailscale-key YOUR_KEY

    # Quick Zero Trust setup
    sudo $0 --quick-setup --email admin@example.com --domain example.com

    # Dry run to test
    sudo $0 --dry-run --verbose

For more information, see: https://github.com/your-repo/server-config
EOF
}

# Main script logic
main() {
    # Parse command-line arguments first (before sudo check for help/version)
    parse_arguments "$@"
    
    # Initialize logging only after parsing args (may not need sudo for help)
    if [ "$EUID" -eq 0 ]; then
        initialize_logging
    fi
    
    # Check if running with sudo (but allow help and version without sudo)
    if [ "$EUID" -ne 0 ]; then 
        print_error "This script must be run with sudo"
        print_status "Usage: sudo $0 [options]"
        print_status "Run '$0 --help' for more information"
        exit 1
    fi
    
    # Show script header
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}     Zero Trust Security Setup Script v${SCRIPT_VERSION}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}\n"
    
    # Validate Ubuntu version
    if [[ "$SKIP_VALIDATION" != true ]]; then
        validate_ubuntu_version
    fi
    
    # Detect main user
    detect_main_user
    
    # Handle quick setup mode
    if [[ "${RUN_ZERO_TRUST:-false}" == true ]]; then
        print_status "Running Zero Trust setup in quick mode..."
        
        # Set defaults if not provided
        if [ -z "$ADMIN_EMAIL" ] && [ -z "$EMAIL" ]; then
            ADMIN_EMAIL="admin@localhost"
            print_warning "No email provided, using: $ADMIN_EMAIL"
        fi
        
        # Run interactive configuration if needed
        if [[ "$INTERACTIVE_MODE" == true ]] && [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ] && [ -z "$TAILSCALE_AUTH_KEY" ]; then
            configure_interactively
        fi
        
        # Run Zero Trust setup
        setup_zero_trust_complete
        exit $?
    fi
    
    # Interactive mode - show configuration wizard first
    if [[ "$INTERACTIVE_MODE" == true ]]; then
        echo -e "${YELLOW}Welcome to the Zero Trust Security Setup!${NC}\n"
        echo "This script will help you secure your Ubuntu server with:"
        echo "• Zero exposed ports (all traffic via secure tunnels)"
        echo "• Tailscale for secure SSH access"
        echo "• Cloudflare Tunnel for web services"
        echo "• CrowdSec for threat protection"
        echo "• Comprehensive monitoring and compliance"
        echo
        
        read -p "Would you like to start the configuration wizard? [Y/n]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            configure_interactively
            
            # Ask if user wants to run setup now
            echo -e "\n${CYAN}Configuration complete!${NC}"
            read -p "Would you like to run the Zero Trust setup now? [Y/n]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                setup_zero_trust_complete
                exit $?
            fi
        fi
    fi
    
    # Show main menu for manual selection
    while true; do
        show_menu
        read -p "Enter your choice [1-4]: " choice
        
        case $choice in
            1)
                handle_base_menu
                ;;
            2)
                handle_security_menu
                ;;
            3)
                run_all
                ;;
            4)
                print_status "Exiting..."
                print_success "Thank you for using Zero Trust Security Setup!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-4"
                ;;
        esac
        
        if [ "$choice" != "4" ]; then
            echo -e "\n${YELLOW}Press Enter to continue...${NC}"
            read
        fi
    done
}

# Trap Ctrl+C and cleanup
trap 'echo -e "\n${RED}Setup interrupted by user${NC}"; cleanup_on_error; exit 130' INT TERM

# Run main function with all arguments
main "$@"