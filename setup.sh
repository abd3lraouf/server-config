#!/bin/bash
# Ubuntu Server Configuration Orchestrator
# Main entry point for modular server setup system
# Version: 2.0.0
# Repository: https://github.com/abd3lraouf/server-config

set -euo pipefail

# ============================================================================
# One-Liner Installation Handler
# ============================================================================
# Skip if we're already running from the curl installation
if [ "${1:-}" != "--from-curl" ]; then
    # Detect if script is being run via curl/wget (one-liner installation)
    if [ ! -t 0 ] || [ "${1:-}" = "--curl-install" ]; then
        echo "🚀 Ubuntu Server Setup - One-Liner Installation"
        echo "================================================"

    # Create temporary directory for installation
    INSTALL_DIR="/tmp/server-config-$$"
    echo "📦 Setting up temporary installation directory..."

    # Clean up any existing installation
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Clone the repository
    echo "📥 Downloading server configuration files..."
    if ! git clone --quiet https://github.com/abd3lraouf/server-config.git .; then
        echo "❌ Failed to download repository. Please check your internet connection."
        exit 1
    fi

    # Make scripts executable
    chmod +x setup.sh
    find src -name "*.sh" -exec chmod +x {} \;

    echo "✅ Download complete. Starting setup..."
    echo ""

        # Execute the actual setup script with remaining arguments
        shift 2>/dev/null || true  # Remove --curl-install if present

        # For curl installations, provide clear instructions since we can't get terminal input
        echo ""
        echo "✨ Installation downloaded successfully!"
        echo ""
        echo "📋 To continue with setup, run one of these commands:"
        echo ""
        echo "  Interactive menu:"
        echo "    cd $INSTALL_DIR && sudo ./setup.sh"
        echo ""
        echo "  Quick setups:"
        echo "    cd $INSTALL_DIR && sudo ./setup.sh basic      # Basic server setup"
        echo "    cd $INSTALL_DIR && sudo ./setup.sh security   # Security hardening"
        echo "    cd $INSTALL_DIR && sudo ./setup.sh dev        # Development environment"
        echo "    cd $INSTALL_DIR && sudo ./setup.sh zero-trust # Complete Zero Trust setup"
        echo ""
        echo "  View all options:"
        echo "    cd $INSTALL_DIR && sudo ./setup.sh --help"
        echo ""
        exit 0
    fi
fi

# Script metadata
readonly SCRIPT_VERSION="2.1.0"
readonly SCRIPT_NAME="Ubuntu Server Setup Orchestrator"
readonly REPO_URL="https://github.com/abd3lraouf/server-config"

# Detect script directory
if [ "${SCRIPT_DIR:-}" = "" ]; then
    readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
readonly SRC_DIR="${SCRIPT_DIR}/src"

# Export for use by modules
export SCRIPT_DIR SRC_DIR

# ============================================================================
# Core Functions
# ============================================================================

# Source library files
source_libraries() {
    local libs=(
        "lib/common.sh"
        "lib/config.sh"
        "lib/validation.sh"
        "lib/backup.sh"
    )

    for lib in "${libs[@]}"; do
        local lib_path="${SRC_DIR}/${lib}"
        if [[ -f "$lib_path" ]]; then
            source "$lib_path"
        else
            echo "ERROR: Required library not found: $lib_path" >&2
            exit 1
        fi
    done
}

# Initialize environment
initialize_environment() {
    # Set default values
    export INTERACTIVE_MODE="${INTERACTIVE_MODE:-true}"
    export VERBOSE="${VERBOSE:-false}"
    export DRY_RUN="${DRY_RUN:-false}"
    export CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/config.env}"

    # Detect system information
    export OS_VERSION="$(lsb_release -rs 2>/dev/null || echo "unknown")"
    export OS_CODENAME="$(lsb_release -cs 2>/dev/null || echo "unknown")"

    # Detect main user (first non-root user)
    if [[ -z "${MAIN_USER:-}" ]]; then
        MAIN_USER=$(getent passwd 1000 | cut -d: -f1 || echo "")
        if [[ -z "$MAIN_USER" ]]; then
            MAIN_USER=$(ls /home 2>/dev/null | head -n 1 || echo "")
        fi
    fi
    export MAIN_USER

    # Load configuration if exists
    if declare -f load_config_file &>/dev/null; then
        load_config_file "$CONFIG_FILE" || true
    fi
}

# ============================================================================
# Module Management
# ============================================================================

# Load a specific module
load_module() {
    local module_path="$1"
    local full_path="${SRC_DIR}/${module_path}"

    if [[ -f "$full_path" ]]; then
        source "$full_path"
        return 0
    else
        print_error "Module not found: $module_path"
        return 1
    fi
}

# List available modules
list_modules() {
    print_header "Available Modules"

    echo "Base Modules:"
    for module in "${SRC_DIR}"/base/*.sh; do
        [[ -f "$module" ]] && echo "  • $(basename "$module")"
    done

    echo ""
    echo "Security Modules:"
    for module in "${SRC_DIR}"/security/*.sh; do
        [[ -f "$module" ]] && echo "  • $(basename "$module")"
    done

    echo ""
    echo "Menu Modules:"
    for module in "${SRC_DIR}"/menu/*.sh; do
        [[ -f "$module" ]] && echo "  • $(basename "$module")"
    done

    if ls "${SRC_DIR}"/containers/*.sh &>/dev/null 2>&1; then
        echo ""
        echo "Container Modules:"
        for module in "${SRC_DIR}"/containers/*.sh; do
            [[ -f "$module" ]] && echo "  • $(basename "$module")"
        done
    fi

    if ls "${SRC_DIR}"/monitoring/*.sh &>/dev/null 2>&1; then
        echo ""
        echo "Monitoring Modules:"
        for module in "${SRC_DIR}"/monitoring/*.sh; do
            [[ -f "$module" ]] && echo "  • $(basename "$module")"
        done
    fi
}

# ============================================================================
# Command Line Interface
# ============================================================================

# Show help message
show_help() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

Usage: $0 [OPTIONS] [COMMAND]

COMMANDS:
    menu                Run interactive menu (default)
    quick               Run quick setup menu
    basic               Run basic server setup
    security            Run security hardening
    development         Setup development environment
    zero-trust          Complete Zero Trust setup
    list                List available modules
    run MODULE          Run specific module

OPTIONS:
    -h, --help          Show this help message
    -v, --version       Show version information
    -n, --non-interactive Run in non-interactive mode
    -c, --config FILE   Use specific config file
    -d, --dry-run       Show what would be done without doing it
    --verbose           Enable verbose output

ENVIRONMENT VARIABLES:
    INTERACTIVE_MODE    Set to 'false' for non-interactive mode
    CONFIG_FILE         Path to configuration file
    MAIN_USER           Main non-root user
    DRY_RUN             Set to 'true' for dry run mode
    VERBOSE             Set to 'true' for verbose output

EXAMPLES:
    # Run interactive menu
    $0

    # Run quick setup
    $0 quick

    # Run specific module
    $0 run security/tailscale.sh --install

    # Non-interactive basic setup
    $0 -n basic

    # Use custom config
    $0 -c /path/to/config.env menu

EOF
}

# Show version
show_version() {
    echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
    echo "Module System: Enabled"
    echo "OS: Ubuntu ${OS_VERSION} (${OS_CODENAME})"
}

# ============================================================================
# Quick Commands
# ============================================================================

# Run basic setup
run_basic() {
    print_header "Basic Server Setup"

    load_module "base/system-update.sh"
    load_module "base/dev-tools.sh"

    # Run setup functions
    system_update
    install_essential_packages
    configure_auto_updates

    print_success "Basic setup completed!"
}

# Run security setup
run_security() {
    print_header "Security Hardening"

    load_module "security/firewall.sh"
    load_module "security/tailscale.sh"

    # Configure firewall
    configure_ufw

    # Optional: Setup Tailscale
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        if confirm_action "Setup Tailscale VPN?"; then
            install_tailscale
            configure_tailscale_interactive
        fi
    fi

    print_success "Security hardening completed!"
}

# Run development setup
run_development() {
    print_header "Development Environment Setup"

    load_module "base/shell-setup.sh"
    load_module "base/dev-tools.sh"

    # Install development tools
    setup_zsh_complete
    setup_dev_complete

    print_success "Development environment setup completed!"
}

# Run Zero Trust setup
run_zero_trust() {
    print_header "Zero Trust Security Setup"

    # Check if Zero Trust orchestrator exists
    if [[ -f "${SRC_DIR}/scripts/zero-trust.sh" ]]; then
        print_status "Launching Zero Trust orchestrator..."
        source "${SRC_DIR}/scripts/zero-trust.sh"
        run_zero_trust_setup
    else
        # Fallback to basic security setup
        print_warning "Full orchestrator not found, running basic security setup..."

        # Load security modules
        load_module "base/system-update.sh"
        load_module "security/firewall.sh"
        load_module "security/tailscale.sh"

        # Run basic setup
        print_status "Phase 1: System Updates"
        system_update
        configure_auto_updates

        print_status "Phase 2: Firewall Configuration"
        configure_ufw
        if command -v docker &>/dev/null; then
            configure_ufw_docker
        fi

        print_status "Phase 3: Tailscale VPN"
        install_tailscale
        if [[ "$INTERACTIVE_MODE" == "true" ]]; then
            configure_tailscale_interactive
        else
            configure_tailscale
        fi

        print_success "Basic security setup completed!"
    fi
}

# Run specific module
run_module() {
    local module="$1"
    shift  # Remove module name from arguments

    # Add .sh extension if not present
    [[ "$module" != *.sh ]] && module="${module}.sh"

    # Try to find module in different locations
    local locations=(
        "$module"
        "base/$module"
        "security/$module"
        "menu/$module"
        "monitoring/$module"
        "containers/$module"
    )

    for location in "${locations[@]}"; do
        if [[ -f "${SRC_DIR}/${location}" ]]; then
            print_status "Running module: $location"
            load_module "$location"

            # If arguments provided, assume they're module-specific commands
            if [[ $# -gt 0 ]]; then
                # Try to execute module with arguments
                bash "${SRC_DIR}/${location}" "$@"
            fi
            return 0
        fi
    done

    print_error "Module not found: $module"
    return 1
}

# Confirm action helper
confirm_action() {
    local prompt="${1:-Continue?}"
    local response

    read -p "$prompt [y/N]: " -n 1 -r response
    echo
    [[ "$response" =~ ^[Yy]$ ]]
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root or with sudo" >&2
        exit 1
    fi

    # Source libraries first
    source_libraries

    # Initialize environment
    initialize_environment

    # Parse command line arguments
    local command=""
    local args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            --from-curl)
                # This flag indicates we're running from the curl installation
                # Just skip it and continue
                shift
                ;;
            -n|--non-interactive)
                export INTERACTIVE_MODE="false"
                shift
                ;;
            -c|--config)
                export CONFIG_FILE="$2"
                shift 2
                ;;
            -d|--dry-run)
                export DRY_RUN="true"
                shift
                ;;
            --verbose)
                export VERBOSE="true"
                shift
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$1"
                else
                    args+=("$1")
                fi
                shift
                ;;
        esac
    done

    # Default to menu if no command
    [[ -z "$command" ]] && command="menu"

    # Execute command
    case "$command" in
        menu)
            load_module "menu/simplified-menu.sh"
            run_quick_setup_menu
            ;;
        quick)
            load_module "menu/simplified-menu.sh"
            run_quick_setup_menu
            ;;
        basic)
            run_basic
            ;;
        security)
            run_security
            ;;
        development|dev)
            run_development
            ;;
        zero-trust|zt)
            run_zero_trust
            ;;
        list|ls)
            list_modules
            ;;
        run)
            if [[ ${#args[@]} -eq 0 ]]; then
                print_error "Module name required"
                echo "Usage: $0 run MODULE [MODULE_ARGS]"
                exit 1
            fi
            run_module "${args[@]}"
            ;;
        *)
            print_error "Unknown command: $command"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"