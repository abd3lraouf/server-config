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

# Function 5: Clean APT sources
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
    install_zsh
    install_oh_my_zsh
    install_powerlevel10k
    deploy_configs
    clean_apt_sources
    
    print_success "All steps completed successfully!"
}

# Function to display menu
show_menu() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          Ubuntu Server Setup Script              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo -e "\n${MAGENTA}Please select an option:${NC}\n"
    echo -e "  ${GREEN}1)${NC} Install Zsh (set as default shell)"
    echo -e "  ${GREEN}2)${NC} Install Oh-My-Zsh"
    echo -e "  ${GREEN}3)${NC} Install Powerlevel10k theme"
    echo -e "  ${GREEN}4)${NC} Deploy configuration files (.zshrc & .p10k.zsh)"
    echo -e "  ${GREEN}5)${NC} Clean APT sources"
    echo -e "  ${GREEN}6)${NC} Run all steps"
    echo -e "  ${GREEN}7)${NC} Exit"
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
        read -p "Enter your choice [1-7]: " choice
        
        case $choice in
            1)
                install_zsh
                ;;
            2)
                install_oh_my_zsh
                ;;
            3)
                install_powerlevel10k
                ;;
            4)
                deploy_configs
                ;;
            5)
                clean_apt_sources
                ;;
            6)
                run_all
                ;;
            7)
                print_status "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-7"
                ;;
        esac
        
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read
    done
}

# Run main function
main "$@"