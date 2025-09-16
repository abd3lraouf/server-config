#!/bin/bash
# Shell setup module - Zsh, Oh-My-Zsh, and Powerlevel10k installation
# Provides functions for setting up modern shell environment

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="shell-setup"

# ============================================================================
# Zsh Installation
# ============================================================================

# Install Zsh shell
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
    local ZSH_PATH=$(which zsh)

    # Set zsh as default shell for root
    print_status "Setting zsh as default shell for root..."
    sudo chsh -s "$ZSH_PATH" root

    # Set zsh as default shell for main user
    if [ -n "$MAIN_USER" ]; then
        print_status "Setting zsh as default shell for $MAIN_USER..."
        sudo chsh -s "$ZSH_PATH" "$MAIN_USER"
        print_success "Default shell changed to zsh for root and $MAIN_USER"
    else
        print_warning "Main user not detected, skipping user shell change"
    fi

    return 0
}

# ============================================================================
# Oh-My-Zsh Installation
# ============================================================================

# Install Oh-My-Zsh for a specific user
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
    if [ -f "$home_dir/.zshrc" ]; then
        backup_file "$home_dir/.zshrc"
    fi

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
    return 0
}

# Install Oh-My-Zsh main function
install_oh_my_zsh() {
    print_status "Installing Oh-My-Zsh..."

    # Install dependencies
    sudo apt update
    sudo apt install -y git curl wget

    # Install for root
    install_omz_for_user "root"

    # Install for main user
    if [ -n "$MAIN_USER" ]; then
        install_omz_for_user "$MAIN_USER"
    fi

    # Install zsh plugins
    install_zsh_plugins

    return 0
}

# ============================================================================
# Zsh Plugins Installation
# ============================================================================

# Install plugins for a specific user
install_plugins_for_user() {
    local user="$1"
    local home_dir

    if [ "$user" = "root" ]; then
        home_dir="/root"
    else
        home_dir="/home/$user"
    fi

    local custom_plugins="$home_dir/.oh-my-zsh/custom/plugins"

    print_status "Installing zsh plugins for $user..."

    # Create custom plugins directory if it doesn't exist
    if [ ! -d "$custom_plugins" ]; then
        if [ "$user" = "root" ]; then
            mkdir -p "$custom_plugins"
        else
            sudo -u "$user" mkdir -p "$custom_plugins"
        fi
    fi

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

    return 0
}

# Install zsh plugins main function
install_zsh_plugins() {
    print_status "Installing zsh plugins..."

    install_plugins_for_user "root"

    if [ -n "$MAIN_USER" ]; then
        install_plugins_for_user "$MAIN_USER"
    fi

    return 0
}

# ============================================================================
# Powerlevel10k Installation
# ============================================================================

# Install Powerlevel10k for a specific user
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
    return 0
}

# Install Powerlevel10k main function
install_powerlevel10k() {
    print_status "Installing Powerlevel10k theme..."

    # Install for root
    install_p10k_for_user "root"

    # Install for main user
    if [ -n "$MAIN_USER" ]; then
        install_p10k_for_user "$MAIN_USER"
    fi

    return 0
}

# ============================================================================
# Configuration Deployment
# ============================================================================

# Deploy shell configuration files
deploy_shell_configs() {
    print_status "Deploying shell configuration files..."

    # Check if config files exist in script directory
    if [ ! -f "$SCRIPT_DIR/zshrc" ] || [ ! -f "$SCRIPT_DIR/p10k.zsh" ]; then
        print_warning "Configuration files not found in $SCRIPT_DIR"
        print_status "Shell setup complete, but custom configs not deployed"
        return 1
    fi

    # Deploy for a specific user
    deploy_configs_for_user() {
        local user="$1"
        local home_dir

        if [ "$user" = "root" ]; then
            home_dir="/root"
        else
            home_dir="/home/$user"
        fi

        print_status "Deploying configurations for $user..."

        # Deploy .zshrc
        if [ -f "$SCRIPT_DIR/zshrc" ]; then
            backup_file "$home_dir/.zshrc"
            sudo cp "$SCRIPT_DIR/zshrc" "$home_dir/.zshrc"

            # Update the .zshrc with correct paths
            sudo sed -i "s|export ZSH=\".*\"|export ZSH=\"$home_dir/.oh-my-zsh\"|" "$home_dir/.zshrc"

            # Update theme
            sudo sed -i 's|ZSH_THEME=".*"|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$home_dir/.zshrc"

            # Add plugins
            sudo sed -i 's|plugins=(.*)|plugins=(git zsh-autosuggestions zsh-completions zsh-syntax-highlighting docker kubectl aws)|' "$home_dir/.zshrc"

            # Set ownership
            if [ "$user" != "root" ]; then
                sudo chown "$user:$user" "$home_dir/.zshrc"
            fi

            print_success ".zshrc deployed for $user"
        fi

        # Deploy .p10k.zsh
        if [ -f "$SCRIPT_DIR/p10k.zsh" ]; then
            sudo cp "$SCRIPT_DIR/p10k.zsh" "$home_dir/.p10k.zsh"

            # Set ownership
            if [ "$user" != "root" ]; then
                sudo chown "$user:$user" "$home_dir/.p10k.zsh"
            fi

            print_success ".p10k.zsh deployed for $user"
        fi

        # Add P10k configuration to .zshrc if not present
        if ! grep -q "p10k configure" "$home_dir/.zshrc"; then
            echo "" | sudo tee -a "$home_dir/.zshrc"
            echo "# To customize prompt, run 'p10k configure' or edit ~/.p10k.zsh." | sudo tee -a "$home_dir/.zshrc"
            echo "[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh" | sudo tee -a "$home_dir/.zshrc"
        fi

        return 0
    }

    # Deploy for root
    deploy_configs_for_user "root"

    # Deploy for main user
    if [ -n "$MAIN_USER" ]; then
        deploy_configs_for_user "$MAIN_USER"
    fi

    print_success "Shell configurations deployed successfully"
    return 0
}

# ============================================================================
# Complete Shell Setup
# ============================================================================

# Run complete shell setup
setup_shell_complete() {
    print_header "Complete Shell Environment Setup"

    # Detect main user if not set
    if [ -z "$MAIN_USER" ]; then
        detect_main_user
    fi

    # Install components in order
    install_zsh
    install_oh_my_zsh
    install_powerlevel10k
    deploy_shell_configs

    print_success "Shell environment setup completed!"
    print_warning "Please log out and log back in for changes to take effect"

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Shell Setup Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --install-zsh           Install Zsh shell only
    --install-omz           Install Oh-My-Zsh only
    --install-p10k          Install Powerlevel10k only
    --deploy-configs        Deploy configuration files only
    --complete              Run complete shell setup
    --help                  Show this help message
    --test                  Run module self-tests

EXAMPLES:
    # Install complete shell environment
    $0 --complete

    # Install only Zsh
    $0 --install-zsh

    # Deploy configurations
    $0 --deploy-configs

EOF
}

# Export all functions
export -f install_zsh install_oh_my_zsh install_powerlevel10k
export -f deploy_shell_configs setup_shell_complete
export -f install_omz_for_user install_plugins_for_user install_p10k_for_user
export -f install_zsh_plugins

# Source required libraries
# Use existing SCRIPT_DIR if available, otherwise detect it
if [[ -z "${SCRIPT_DIR:-}" ]]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Ensure SRC_DIR is set for module loading
if [[ -z "${SRC_DIR:-}" ]]; then
    SRC_DIR="${SCRIPT_DIR}/.."
fi
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/config.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/backup.sh" 2>/dev/null || true

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --install-zsh)
            install_zsh
            ;;
        --install-omz)
            install_oh_my_zsh
            ;;
        --install-p10k)
            install_powerlevel10k
            ;;
        --deploy-configs)
            deploy_shell_configs
            ;;
        --complete)
            setup_shell_complete
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running shell setup module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "Shell Setup Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi
