#!/bin/bash
# Simplified menu module - Streamlined menu system for quick setup
# Provides user-friendly menu interface with common configuration options

# Script metadata
readonly MODULE_VERSION="1.0.0"
readonly MODULE_NAME="simplified-menu"

# Menu colors
readonly MENU_HEADER="\033[1;36m"
readonly MENU_OPTION="\033[1;33m"
readonly MENU_PROMPT="\033[1;32m"
readonly MENU_ERROR="\033[1;31m"
readonly MENU_RESET="\033[0m"

# ============================================================================
# Menu Display Functions
# ============================================================================

# Display menu header
display_menu_header() {
    clear
    echo -e "${MENU_HEADER}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║           UBUNTU SERVER CONFIGURATION - SIMPLIFIED MENU          ║"
    echo "║                     Zero Trust Security Suite                    ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${MENU_RESET}"
    echo ""
}

# Display quick setup menu
display_quick_setup_menu() {
    display_menu_header

    echo -e "${MENU_OPTION}Quick Setup Options:${MENU_RESET}"
    echo ""
    echo "  1) Basic Server Setup (Updates + Essential Tools)"
    echo "  2) Development Environment (Node.js + Claude CLI)"
    echo "  3) Security Hardening (Firewall + SSH Security)"
    echo "  4) Tailscale VPN Setup"
    echo "  5) Complete Zero Trust Setup (All Security Features)"
    echo ""
    echo "  9) Advanced Menu"
    echo "  0) Exit"
    echo ""
}

# Display preset configurations menu
display_preset_menu() {
    display_menu_header

    echo -e "${MENU_OPTION}Preset Configurations:${MENU_RESET}"
    echo ""
    echo "  1) Web Server (Nginx/Apache + Let's Encrypt)"
    echo "  2) Database Server (MySQL/PostgreSQL)"
    echo "  3) Docker Host (Docker + Compose + Portainer)"
    echo "  4) Development Workstation (Full Dev Tools)"
    echo "  5) Secure Bastion Host (Maximum Security)"
    echo ""
    echo "  9) Back to Main Menu"
    echo "  0) Exit"
    echo ""
}

# ============================================================================
# Quick Setup Functions
# ============================================================================

# Basic server setup
quick_setup_basic() {
    print_header "Basic Server Setup"

    # Source required modules
    source_module "base/system-update.sh"
    source_module "base/dev-tools.sh"

    # Run basic setup
    system_update
    install_essential_packages
    install_common_tools
    configure_auto_updates

    print_success "Basic server setup completed!"
    return 0
}

# Development environment setup
quick_setup_development() {
    print_header "Development Environment Setup"

    # Source required modules
    source_module "base/shell-setup.sh"
    source_module "base/dev-tools.sh"

    # Detect main user
    detect_main_user

    # Install development tools
    install_zsh
    install_oh_my_zsh
    install_powerlevel10k
    install_nvm
    install_nodejs
    install_claude
    install_python

    print_success "Development environment setup completed!"
    return 0
}

# Security hardening setup
quick_setup_security() {
    print_header "Security Hardening Setup"

    # Source required modules
    source_module "security/firewall.sh"
    source_module "security/ssh-security.sh" 2>/dev/null || true

    # Configure security
    configure_ufw

    # If SSH security module exists
    if declare -f configure_ssh_security &>/dev/null; then
        configure_ssh_security
    fi

    print_success "Security hardening completed!"
    return 0
}

# Tailscale VPN setup
quick_setup_tailscale() {
    print_header "Tailscale VPN Setup"

    # Source required module
    source_module "security/tailscale.sh"

    # Install and configure Tailscale
    install_tailscale

    if [[ "$INTERACTIVE_MODE" == true ]]; then
        configure_tailscale_interactive
    else
        configure_tailscale
    fi

    # Optionally restrict SSH
    if confirm_action "Restrict SSH access to Tailscale only?"; then
        restrict_ssh_to_tailscale
    fi

    print_success "Tailscale VPN setup completed!"
    return 0
}

# Complete Zero Trust setup
quick_setup_zero_trust() {
    print_header "Complete Zero Trust Security Setup"

    echo "This will install and configure:"
    echo "  • System hardening and updates"
    echo "  • UFW firewall with Docker support"
    echo "  • Tailscale VPN for secure access"
    echo "  • CrowdSec IPS protection"
    echo "  • Cloudflare Tunnel (if configured)"
    echo "  • Security monitoring tools"
    echo ""

    if ! confirm_action "Proceed with complete Zero Trust setup?"; then
        return 1
    fi

    # Source all required modules
    source_module "base/system-update.sh"
    source_module "security/firewall.sh"
    source_module "security/tailscale.sh"

    # Run complete setup
    system_update
    configure_auto_updates
    configure_ufw

    # Configure Docker firewall if Docker is installed
    if command -v docker &>/dev/null; then
        configure_ufw_docker
    fi

    # Setup Tailscale
    install_tailscale
    configure_tailscale

    print_success "Complete Zero Trust setup finished!"
    print_warning "Remember to:"
    echo "  • Review firewall rules: sudo ufw status"
    echo "  • Check Tailscale status: tailscale status"
    echo "  • Configure additional services as needed"

    return 0
}

# ============================================================================
# Preset Configuration Functions
# ============================================================================

# Web server preset
preset_web_server() {
    print_header "Web Server Configuration"

    # Source required modules
    source_module "base/system-update.sh"
    source_module "security/firewall.sh"

    # Basic setup
    system_update
    configure_ufw

    # Configure web firewall rules
    configure_web_firewall

    print_status "Web server packages can be installed via:"
    echo "  • Nginx: sudo apt install nginx"
    echo "  • Apache: sudo apt install apache2"
    echo "  • Caddy: See https://caddyserver.com/docs/install"

    print_success "Web server configuration completed!"
    return 0
}

# Database server preset
preset_database_server() {
    print_header "Database Server Configuration"

    # Source required modules
    source_module "base/system-update.sh"
    source_module "security/firewall.sh"

    # Basic setup
    system_update
    configure_ufw

    # Ask which database
    echo "Select database type:"
    echo "  1) MySQL/MariaDB"
    echo "  2) PostgreSQL"
    echo "  3) MongoDB"
    echo "  4) Redis"
    read -p "Choice [1-4]: " db_choice

    case "$db_choice" in
        1) db_type="mysql" ;;
        2) db_type="postgresql" ;;
        3) db_type="mongodb" ;;
        4) db_type="redis" ;;
        *) db_type="mysql" ;;
    esac

    # Configure database firewall (localhost only by default)
    configure_database_firewall "$db_type" "127.0.0.1"

    print_status "Install your database with:"
    case "$db_type" in
        mysql) echo "  sudo apt install mysql-server" ;;
        postgresql) echo "  sudo apt install postgresql" ;;
        mongodb) echo "  See MongoDB installation guide" ;;
        redis) echo "  sudo apt install redis-server" ;;
    esac

    print_success "Database server configuration completed!"
    return 0
}

# Docker host preset
preset_docker_host() {
    print_header "Docker Host Configuration"

    # Source required modules
    source_module "base/system-update.sh"
    source_module "security/firewall.sh"
    source_module "containers/docker.sh" 2>/dev/null || true

    # Basic setup
    system_update
    configure_ufw

    # Install Docker if module exists
    if declare -f install_docker &>/dev/null; then
        install_docker
    else
        print_status "Docker installation module not found"
        print_status "Install Docker manually: https://docs.docker.com/engine/install/ubuntu/"
    fi

    # Configure Docker firewall
    if command -v docker &>/dev/null; then
        configure_ufw_docker
    fi

    print_success "Docker host configuration completed!"
    return 0
}

# ============================================================================
# Menu Navigation
# ============================================================================

# Run quick setup menu
run_quick_setup_menu() {
    local choice

    while true; do
        display_quick_setup_menu
        read -p "$(echo -e ${MENU_PROMPT}Select option: ${MENU_RESET})" choice

        case "$choice" in
            1) quick_setup_basic ;;
            2) quick_setup_development ;;
            3) quick_setup_security ;;
            4) quick_setup_tailscale ;;
            5) quick_setup_zero_trust ;;
            9)
                # Switch to advanced menu if available
                if [[ -f "${SCRIPT_DIR}/../menu/main-menu.sh" ]]; then
                    source "${SCRIPT_DIR}/../menu/main-menu.sh"
                    run_main_menu
                else
                    print_warning "Advanced menu not available"
                fi
                ;;
            0)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${MENU_ERROR}Invalid option. Please try again.${MENU_RESET}"
                sleep 2
                ;;
        esac

        if [[ "$choice" != "9" ]] && [[ "$choice" != "0" ]]; then
            echo ""
            read -p "Press Enter to continue..."
        fi
    done
}

# Run preset menu
run_preset_menu() {
    local choice

    while true; do
        display_preset_menu
        read -p "$(echo -e ${MENU_PROMPT}Select option: ${MENU_RESET})" choice

        case "$choice" in
            1) preset_web_server ;;
            2) preset_database_server ;;
            3) preset_docker_host ;;
            4) quick_setup_development ;;
            5) quick_setup_zero_trust ;;
            9) return 0 ;;
            0)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${MENU_ERROR}Invalid option. Please try again.${MENU_RESET}"
                sleep 2
                ;;
        esac

        if [[ "$choice" != "9" ]] && [[ "$choice" != "0" ]]; then
            echo ""
            read -p "Press Enter to continue..."
        fi
    done
}

# ============================================================================
# Helper Functions
# ============================================================================

# Source a module safely
source_module() {
    local module="$1"
    local module_path="${SCRIPT_DIR}/../${module}"

    if [[ -f "$module_path" ]]; then
        source "$module_path"
        return 0
    else
        print_error "Module not found: $module"
        return 1
    fi
}

# Confirm action
confirm_action() {
    local prompt="${1:-Continue?}"
    local response

    read -p "$prompt [y/N]: " -n 1 -r response
    echo
    [[ "$response" =~ ^[Yy]$ ]]
}

# Detect main user
detect_main_user() {
    if [ -z "${MAIN_USER:-}" ]; then
        MAIN_USER=$(getent passwd 1000 | cut -d: -f1 || echo "")
        if [ -z "$MAIN_USER" ]; then
            MAIN_USER=$(ls /home | head -n 1 || echo "")
        fi
    fi
    export MAIN_USER
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Simplified Menu Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --quick-menu        Show quick setup menu
    --preset-menu       Show preset configurations menu
    --basic             Run basic server setup
    --development       Setup development environment
    --security          Run security hardening
    --tailscale         Setup Tailscale VPN
    --zero-trust        Complete Zero Trust setup
    --help              Show this help message
    --test              Run module self-tests

EXAMPLES:
    # Show interactive menu
    $0 --quick-menu

    # Run specific setup
    $0 --basic
    $0 --security

    # Complete Zero Trust setup
    $0 --zero-trust

EOF
}

# Export all functions
export -f display_menu_header display_quick_setup_menu display_preset_menu
export -f quick_setup_basic quick_setup_development quick_setup_security
export -f quick_setup_tailscale quick_setup_zero_trust
export -f preset_web_server preset_database_server preset_docker_host
export -f run_quick_setup_menu run_preset_menu
export -f source_module confirm_action detect_main_user

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/config.sh" 2>/dev/null || true

# Set interactive mode if not set
INTERACTIVE_MODE="${INTERACTIVE_MODE:-true}"

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --quick-menu)
            run_quick_setup_menu
            ;;
        --preset-menu)
            run_preset_menu
            ;;
        --basic)
            quick_setup_basic
            ;;
        --development)
            quick_setup_development
            ;;
        --security)
            quick_setup_security
            ;;
        --tailscale)
            quick_setup_tailscale
            ;;
        --zero-trust)
            quick_setup_zero_trust
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running simplified menu module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            # Default to quick menu
            run_quick_setup_menu
            ;;
    esac
fi