#!/bin/bash

# Ubuntu Server Setup Script
# Configures zsh, oh-my-zsh, powerlevel10k, and system utilities

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MAIN_USER=""
BACKUP_DIR="${HOME}/.config-backup-$(date +%Y%m%d-%H%M%S)"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
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
        read -p "Please enter the username of the main user: " MAIN_USER
    fi
    
    if ! id "$MAIN_USER" &>/dev/null; then
        print_error "User $MAIN_USER does not exist"
        return 1
    fi
    
    print_success "Main user detected: $MAIN_USER"
    return 0
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
            bash -c "source $home_dir/.nvm/nvm.sh && npm install -g @anthropic-ai/claude-cli"
        else
            sudo -u "$user" bash -c "source $home_dir/.nvm/nvm.sh && npm install -g @anthropic-ai/claude-cli"
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

# Function to display menu
show_menu() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          Ubuntu Server Setup Script              ║${NC}"
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
    echo -e "  ${GREEN}10)${NC} Configure UFW Firewall (SSH only)"
    echo -e "  ${GREEN}11)${NC} Configure SSH for Coolify"
    echo -e "  ${GREEN}12)${NC} Install Coolify"
    echo -e "  ${GREEN}13)${NC} Clean APT sources"
    echo -e "  ${GREEN}14)${NC} Run all steps"
    echo -e "  ${GREEN}15)${NC} Exit"
    echo -e "\n${CYAN}════════════════════════════════════════════════════${NC}"
}

# Main script logic
main() {
    # Check if running with sudo
    if [ "$EUID" -ne 0 ]; then 
        print_error "Please run this script with sudo"
        exit 1
    fi
    
    # Detect main user at start
    detect_main_user
    
    while true; do
        show_menu
        read -p "Enter your choice [1-15]: " choice
        
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
                configure_ufw
                ;;
            11)
                configure_ssh_coolify
                ;;
            12)
                install_coolify
                ;;
            13)
                clean_apt_sources
                ;;
            14)
                run_all
                ;;
            15)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-15"
                ;;
        esac
        
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read
    done
}

# Run main function
main "$@"