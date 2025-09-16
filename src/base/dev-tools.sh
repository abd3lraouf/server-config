#!/bin/bash
# Development tools module - NVM, Node.js, Claude CLI, and system tools
# Provides functions for setting up development environment

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="dev-tools"

# NVM version
readonly NVM_VERSION="${NVM_VERSION:-v0.40.3}"

# ============================================================================
# NVM Installation
# ============================================================================

# Install NVM for a specific user
install_nvm_for_user() {
    local user="$1"
    local home_dir

    if [ "$user" = "root" ]; then
        home_dir="/root"
    else
        home_dir="/home/$user"
    fi

    print_status "Installing NVM for $user..."

    # Check if NVM is already installed
    if [ -d "$home_dir/.nvm" ]; then
        print_warning "NVM already installed for $user"
        return 0
    fi

    # Download and install NVM
    if [ "$user" = "root" ]; then
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
    else
        sudo -u "$user" bash -c "curl -o- 'https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh' | bash"
    fi

    # Add NVM to .zshrc if not already present
    if [ -f "$home_dir/.zshrc" ] && ! grep -q "NVM_DIR" "$home_dir/.zshrc" 2>/dev/null; then
        cat >> "$home_dir/.zshrc" << 'EOF'

# NVM Configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
EOF
        if [ "$user" != "root" ]; then
            sudo chown "$user:$user" "$home_dir/.zshrc"
        fi
    fi

    # Also add to .bashrc for compatibility
    if [ -f "$home_dir/.bashrc" ] && ! grep -q "NVM_DIR" "$home_dir/.bashrc" 2>/dev/null; then
        cat >> "$home_dir/.bashrc" << 'EOF'

# NVM Configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
EOF
        if [ "$user" != "root" ]; then
            sudo chown "$user:$user" "$home_dir/.bashrc"
        fi
    fi

    print_success "NVM installed for $user"
    return 0
}

# Install NVM main function
install_nvm() {
    print_status "Installing NVM (Node Version Manager)..."

    # Install dependencies
    sudo apt update
    sudo apt install -y curl

    # Install for root
    install_nvm_for_user "root"

    # Install for main user
    if [ -n "$MAIN_USER" ]; then
        install_nvm_for_user "$MAIN_USER"
    fi

    return 0
}

# ============================================================================
# Node.js Installation
# ============================================================================

# Install Node.js for a specific user
install_node_for_user() {
    local user="$1"
    local node_version="${2:---lts}"  # Default to LTS
    local home_dir

    if [ "$user" = "root" ]; then
        home_dir="/root"
    else
        home_dir="/home/$user"
    fi

    print_status "Installing Node.js for $user..."

    # Check if NVM is installed
    if [ ! -d "$home_dir/.nvm" ]; then
        print_warning "NVM not found for $user, installing it first..."
        install_nvm_for_user "$user"
    fi

    # Source NVM and install Node.js
    if [ "$user" = "root" ]; then
        bash -c "source $home_dir/.nvm/nvm.sh && nvm install $node_version && nvm use $node_version && nvm alias default node"
    else
        sudo -u "$user" bash -c "source $home_dir/.nvm/nvm.sh && nvm install $node_version && nvm use $node_version && nvm alias default node"
    fi

    print_success "Node.js installed for $user"
    return 0
}

# Install Node.js main function
install_nodejs() {
    print_status "Installing Node.js via NVM..."

    # Install for root
    install_node_for_user "root"

    # Install for main user
    if [ -n "$MAIN_USER" ]; then
        install_node_for_user "$MAIN_USER"
    fi

    return 0
}

# ============================================================================
# Claude CLI Installation
# ============================================================================

# Install Claude CLI for a specific user
install_claude_for_user() {
    local user="$1"
    local home_dir

    if [ "$user" = "root" ]; then
        home_dir="/root"
    else
        home_dir="/home/$user"
    fi

    print_status "Installing Claude CLI for $user..."

    # Check if Node.js is installed
    if [ "$user" = "root" ]; then
        if ! bash -c "source $home_dir/.nvm/nvm.sh && command -v node" &>/dev/null; then
            print_warning "Node.js not found for $user, installing it first..."
            install_node_for_user "$user"
        fi
    else
        if ! sudo -u "$user" bash -c "source $home_dir/.nvm/nvm.sh && command -v node" &>/dev/null; then
            print_warning "Node.js not found for $user, installing it first..."
            install_node_for_user "$user"
        fi
    fi

    # Install Claude CLI globally via npm
    if [ "$user" = "root" ]; then
        bash -c "source $home_dir/.nvm/nvm.sh && npm install -g @anthropic-ai/claude-code"
    else
        sudo -u "$user" bash -c "source $home_dir/.nvm/nvm.sh && npm install -g @anthropic-ai/claude-code"
    fi

    print_success "Claude CLI installed for $user"
    print_warning "Remember to run 'claude login' to authenticate"

    return 0
}

# Install Claude CLI main function
install_claude() {
    print_status "Installing Claude CLI..."

    # Install for root
    install_claude_for_user "root"

    # Install for main user
    if [ -n "$MAIN_USER" ]; then
        install_claude_for_user "$MAIN_USER"
    fi

    return 0
}

# ============================================================================
# System Tools Installation
# ============================================================================

# Install htop system monitor
install_htop() {
    print_status "Installing htop system monitor..."

    if command -v htop &>/dev/null; then
        print_warning "htop is already installed"
        return 0
    fi

    sudo apt update
    sudo apt install -y htop

    print_success "htop installed successfully"
    return 0
}

# Install common development tools
install_common_tools() {
    print_status "Installing common development tools..."

    local tools=(
        "git"
        "curl"
        "wget"
        "vim"
        "nano"
        "build-essential"
        "software-properties-common"
        "apt-transport-https"
        "ca-certificates"
        "gnupg"
        "lsb-release"
        "tree"
        "jq"
        "zip"
        "unzip"
        "net-tools"
        "dnsutils"
        "telnet"
        "ncdu"
        "tmux"
        "screen"
    )

    sudo apt update

    for tool in "${tools[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$tool"; then
            print_status "Installing $tool..."
            sudo apt install -y "$tool"
        else
            print_debug "$tool is already installed"
        fi
    done

    print_success "Common development tools installed"
    return 0
}

# Install Python and pip
install_python() {
    print_status "Installing Python and pip..."

    sudo apt update
    sudo apt install -y python3 python3-pip python3-venv

    # Create python symlink if it doesn't exist
    if ! command -v python &>/dev/null; then
        sudo ln -sf /usr/bin/python3 /usr/bin/python
    fi

    print_success "Python and pip installed"
    return 0
}

# Install Docker CLI tools
install_docker_cli_tools() {
    print_status "Installing Docker CLI tools..."

    # Install docker-compose
    if ! command -v docker-compose &>/dev/null; then
        print_status "Installing docker-compose..."
        sudo apt update
        sudo apt install -y docker-compose
    fi

    # Install lazydocker
    if ! command -v lazydocker &>/dev/null; then
        print_status "Installing lazydocker..."
        curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
    fi

    print_success "Docker CLI tools installed"
    return 0
}

# ============================================================================
# Complete Development Setup
# ============================================================================

# Run complete development tools setup
setup_dev_complete() {
    print_header "Complete Development Environment Setup"

    # Detect main user if not set
    if [ -z "$MAIN_USER" ]; then
        detect_main_user
    fi

    # Install components in order
    install_common_tools
    install_python
    install_nvm
    install_nodejs
    install_claude
    install_htop

    # Optional: Install Docker CLI tools if Docker is present
    if command -v docker &>/dev/null; then
        install_docker_cli_tools
    fi

    print_success "Development environment setup completed!"
    print_warning "Please restart your shell or source your profile for changes to take effect"

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Development Tools Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --install-nvm           Install NVM (Node Version Manager)
    --install-nodejs        Install Node.js via NVM
    --install-claude        Install Claude CLI
    --install-htop          Install htop system monitor
    --install-common        Install common development tools
    --install-python        Install Python and pip
    --install-docker-tools  Install Docker CLI tools
    --complete              Run complete development setup
    --help                  Show this help message
    --test                  Run module self-tests

EXAMPLES:
    # Install complete development environment
    $0 --complete

    # Install only Node.js environment
    $0 --install-nvm --install-nodejs

    # Install Claude CLI
    $0 --install-claude

EOF
}

# Run module tests
run_tests() {
    print_header "Running Development Tools Module Tests"

    local tests_passed=0
    local tests_failed=0

    # Test: Check if functions are defined
    if declare -f install_nvm &>/dev/null; then
        echo "✓ install_nvm function defined"
        ((tests_passed++))
    else
        echo "✗ install_nvm function not defined"
        ((tests_failed++))
    fi

    if declare -f install_nodejs &>/dev/null; then
        echo "✓ install_nodejs function defined"
        ((tests_passed++))
    else
        echo "✗ install_nodejs function not defined"
        ((tests_failed++))
    fi

    echo ""
    echo "Tests passed: $tests_passed"
    echo "Tests failed: $tests_failed"

    return $tests_failed
}

# Export all functions
export -f install_nvm install_nodejs install_claude install_htop
export -f install_common_tools install_python install_docker_cli_tools
export -f setup_dev_complete install_nvm_for_user install_node_for_user
export -f install_claude_for_user

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

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --install-nvm)
            install_nvm
            ;;
        --install-nodejs)
            install_nodejs
            ;;
        --install-claude)
            install_claude
            ;;
        --install-htop)
            install_htop
            ;;
        --install-common)
            install_common_tools
            ;;
        --install-python)
            install_python
            ;;
        --install-docker-tools)
            install_docker_cli_tools
            ;;
        --complete)
            setup_dev_complete
            ;;
        --help)
            show_help
            ;;
        --test)
            run_tests
            ;;
        *)
            echo "Development Tools Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi
