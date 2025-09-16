#!/bin/bash
# Configuration management library
# Handles loading, saving, and managing configuration values

# Library metadata
[[ -z "${LIB_CONFIG_VERSION:-}" ]] && readonly LIB_CONFIG_VERSION="1.0.0"
[[ -z "${LIB_CONFIG_NAME:-}" ]] && readonly LIB_CONFIG_NAME="config"

# Default configuration values
declare -g MAIN_USER="${MAIN_USER:-}"
declare -g ADMIN_EMAIL="${ADMIN_EMAIL:-}"
declare -g DOMAIN_NAME="${DOMAIN_NAME:-}"
declare -g INTERACTIVE_MODE="${INTERACTIVE_MODE:-true}"
declare -g DRY_RUN="${DRY_RUN:-false}"
declare -g VERBOSE="${VERBOSE:-false}"
declare -g SKIP_VALIDATION="${SKIP_VALIDATION:-false}"

# Service configuration
declare -g CLOUDFLARE_EMAIL="${CLOUDFLARE_EMAIL:-}"
declare -g CLOUDFLARE_API_KEY="${CLOUDFLARE_API_KEY:-}"
declare -g CLOUDFLARE_TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN:-}"
declare -g CLOUDFLARE_TUNNEL_NAME="${CLOUDFLARE_TUNNEL_NAME:-}"
declare -g USE_NATIVE_CLOUDFLARED="${USE_NATIVE_CLOUDFLARED:-true}"

declare -g TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
declare -g TAILSCALE_ADVERTISE_ROUTES="${TAILSCALE_ADVERTISE_ROUTES:-}"
declare -g TAILSCALE_TAGS="${TAILSCALE_TAGS:-}"
declare -g TAILSCALE_ACCEPT_ROUTES="${TAILSCALE_ACCEPT_ROUTES:-false}"
declare -g TAILSCALE_SSH="${TAILSCALE_SSH:-true}"

# Container runtime options
declare -g ENABLE_ROOTLESS_DOCKER="${ENABLE_ROOTLESS_DOCKER:-false}"
declare -g ENABLE_PODMAN="${ENABLE_PODMAN:-false}"

# Security options
declare -g ENABLE_AUTO_UPDATES="${ENABLE_AUTO_UPDATES:-true}"
declare -g ENABLE_CIS_HARDENING="${ENABLE_CIS_HARDENING:-true}"
declare -g ENABLE_PAM_HARDENING="${ENABLE_PAM_HARDENING:-true}"
declare -g ENABLE_KERNEL_HARDENING="${ENABLE_KERNEL_HARDENING:-true}"
declare -g ENABLE_APPARMOR="${ENABLE_APPARMOR:-true}"
declare -g ENABLE_AUDIT="${ENABLE_AUDIT:-true}"

# Service ports
declare -g CROWDSEC_PORT="${CROWDSEC_PORT:-8090}"

# Export all configuration variables
export MAIN_USER ADMIN_EMAIL DOMAIN_NAME INTERACTIVE_MODE DRY_RUN VERBOSE SKIP_VALIDATION
export CLOUDFLARE_EMAIL CLOUDFLARE_API_KEY CLOUDFLARE_TUNNEL_TOKEN CLOUDFLARE_TUNNEL_NAME
export USE_NATIVE_CLOUDFLARED TAILSCALE_AUTH_KEY TAILSCALE_ADVERTISE_ROUTES
export TAILSCALE_TAGS TAILSCALE_ACCEPT_ROUTES TAILSCALE_SSH
export ENABLE_ROOTLESS_DOCKER ENABLE_PODMAN
export ENABLE_AUTO_UPDATES ENABLE_CIS_HARDENING ENABLE_PAM_HARDENING
export ENABLE_KERNEL_HARDENING ENABLE_APPARMOR ENABLE_AUDIT
export CROWDSEC_PORT

# ============================================================================
# Configuration Loading
# ============================================================================

# Load configuration from file
load_config_file() {
    local config_file="${1:-${SCRIPT_DIR}/config}"

    if [[ -f "$config_file" ]]; then
        print_status "Loading configuration from $config_file..."

        # Source the config file in a subshell to validate it first
        if ( source "$config_file" ) 2>/dev/null; then
            source "$config_file"
            print_success "Configuration loaded successfully"
            return 0
        else
            print_warning "Configuration file exists but contains errors"
            return 1
        fi
    else
        print_debug "No configuration file found at $config_file"
        return 1
    fi
}

# ============================================================================
# Configuration Saving
# ============================================================================

# Save current configuration to file
save_config_file() {
    local config_file="${1:-${SCRIPT_DIR}/config}"

    print_status "Saving current configuration to $config_file..."

    # Create config header
    cat > "$config_file" << EOF
#!/bin/bash
# Zero Trust Setup Configuration File
# Generated on: $(date)
# This file contains your saved configuration values
# Edit carefully - this file is sourced by setup.sh

# ============================================================================
# Core Configuration
# ============================================================================

MAIN_USER="${MAIN_USER}"
ADMIN_EMAIL="${ADMIN_EMAIL}"
DOMAIN_NAME="${DOMAIN_NAME}"

# ============================================================================
# Cloudflare Configuration
# ============================================================================

CLOUDFLARE_TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN}"
CLOUDFLARE_TUNNEL_NAME="${CLOUDFLARE_TUNNEL_NAME}"
USE_NATIVE_CLOUDFLARED="${USE_NATIVE_CLOUDFLARED}"

# ============================================================================
# Tailscale Configuration
# ============================================================================

TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY}"
TAILSCALE_ADVERTISE_ROUTES="${TAILSCALE_ADVERTISE_ROUTES}"
TAILSCALE_TAGS="${TAILSCALE_TAGS}"
TAILSCALE_ACCEPT_ROUTES="${TAILSCALE_ACCEPT_ROUTES}"
TAILSCALE_SSH="${TAILSCALE_SSH}"

# ============================================================================
# Container Runtime Configuration
# ============================================================================

ENABLE_ROOTLESS_DOCKER="${ENABLE_ROOTLESS_DOCKER}"
ENABLE_PODMAN="${ENABLE_PODMAN}"

# ============================================================================
# Security Configuration
# ============================================================================

ENABLE_AUTO_UPDATES="${ENABLE_AUTO_UPDATES}"
ENABLE_CIS_HARDENING="${ENABLE_CIS_HARDENING}"
ENABLE_PAM_HARDENING="${ENABLE_PAM_HARDENING}"
ENABLE_KERNEL_HARDENING="${ENABLE_KERNEL_HARDENING}"
ENABLE_APPARMOR="${ENABLE_APPARMOR}"
ENABLE_AUDIT="${ENABLE_AUDIT}"

# ============================================================================
# Service Ports
# ============================================================================

CROWDSEC_PORT="${CROWDSEC_PORT}"

# ============================================================================
# Runtime Options
# ============================================================================

INTERACTIVE_MODE="${INTERACTIVE_MODE}"
DRY_RUN="${DRY_RUN}"
VERBOSE="${VERBOSE}"
SKIP_VALIDATION="${SKIP_VALIDATION}"
EOF

    # Set appropriate permissions
    chmod 600 "$config_file"

    print_success "Configuration saved to $config_file"
    print_status "Note: This file contains sensitive data and is excluded from git"
    return 0
}

# ============================================================================
# Configuration Management
# ============================================================================

# Prompt to save configuration
prompt_save_config() {
    if [[ "$INTERACTIVE_MODE" == true ]]; then
        echo
        read -p "Would you like to save this configuration for future use? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            save_config_file
        fi
    fi
}

# Initialize configuration with priority:
# 1. Command line arguments (highest priority)
# 2. Environment variables
# 3. Config file
# 4. Interactive prompts (if enabled)
initialize_configuration() {
    # First, try to load from config file
    load_config_file || true

    # Then override with environment variables if set (check both old and new names)
    # Use if statements to avoid exit on empty variables with set -e
    if [[ -n "${ADMIN_EMAIL:-}" ]]; then ADMIN_EMAIL="${ADMIN_EMAIL}"; fi
    if [[ -n "${EMAIL:-}" ]]; then ADMIN_EMAIL="${EMAIL}"; fi
    if [[ -n "${DOMAIN_NAME:-}" ]]; then DOMAIN_NAME="${DOMAIN_NAME}"; fi
    if [[ -n "${DOMAIN:-}" ]]; then DOMAIN_NAME="${DOMAIN}"; fi
    if [[ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then CLOUDFLARE_TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN}"; fi
    if [[ -n "${CLOUDFLARE_TOKEN:-}" ]]; then CLOUDFLARE_TUNNEL_TOKEN="${CLOUDFLARE_TOKEN}"; fi
    if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY}"; fi
    if [[ -n "${TAILSCALE_KEY:-}" ]]; then TAILSCALE_AUTH_KEY="${TAILSCALE_KEY}"; fi

    # Command line arguments will override later in parse_arguments()

    print_debug "Configuration initialized"
    return 0  # Ensure function always succeeds
}

# ============================================================================
# Configuration Display
# ============================================================================

# Display current configuration (with sensitive data masked)
show_configuration() {
    echo ""
    print_header "Current Configuration"
    echo ""
    echo "Core Settings:"
    echo "  Main User: ${MAIN_USER:-<not set>}"
    echo "  Admin Email: ${ADMIN_EMAIL:-<not set>}"
    echo "  Domain Name: ${DOMAIN_NAME:-<not set>}"
    echo ""
    echo "Security Settings:"
    echo "  Auto Updates: ${ENABLE_AUTO_UPDATES}"
    echo "  CIS Hardening: ${ENABLE_CIS_HARDENING}"
    echo "  PAM Hardening: ${ENABLE_PAM_HARDENING}"
    echo "  Kernel Hardening: ${ENABLE_KERNEL_HARDENING}"
    echo "  AppArmor: ${ENABLE_APPARMOR}"
    echo "  Audit: ${ENABLE_AUDIT}"
    echo ""
    echo "Services:"
    if [[ -n "${CLOUDFLARE_TUNNEL_TOKEN}" ]]; then
        echo "  Cloudflare Tunnel: Configured (token: ${CLOUDFLARE_TUNNEL_TOKEN:0:10}...)"
    else
        echo "  Cloudflare Tunnel: Not configured"
    fi
    if [[ -n "${TAILSCALE_AUTH_KEY}" ]]; then
        echo "  Tailscale: Configured (key: ${TAILSCALE_AUTH_KEY:0:10}...)"
    else
        echo "  Tailscale: Not configured"
    fi
    echo ""
    echo "Runtime Options:"
    echo "  Interactive Mode: ${INTERACTIVE_MODE}"
    echo "  Dry Run: ${DRY_RUN}"
    echo "  Verbose: ${VERBOSE}"
    echo "  Skip Validation: ${SKIP_VALIDATION}"
    echo ""
}

# ============================================================================
# Configuration Validation
# ============================================================================

# Validate configuration completeness
validate_configuration() {
    local errors=0

    # Check required fields for full setup
    if [[ -z "${ADMIN_EMAIL}" ]]; then
        print_warning "Admin email not configured"
        ((errors++))
    fi

    if [[ -z "${DOMAIN_NAME}" ]]; then
        print_warning "Domain name not configured"
        ((errors++))
    fi

    if [[ -z "${MAIN_USER}" ]]; then
        print_warning "Main user not configured"
        ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        print_warning "Configuration is incomplete. Some features may not work."
        return 1
    fi

    print_success "Configuration validated successfully"
    return 0
}

# ============================================================================
# Configuration Reset
# ============================================================================

# Reset configuration to defaults
reset_configuration() {
    print_warning "Resetting configuration to defaults..."

    MAIN_USER=""
    ADMIN_EMAIL=""
    DOMAIN_NAME=""
    CLOUDFLARE_TUNNEL_TOKEN=""
    CLOUDFLARE_TUNNEL_NAME=""
    TAILSCALE_AUTH_KEY=""
    TAILSCALE_ADVERTISE_ROUTES=""
    TAILSCALE_TAGS=""

    print_success "Configuration reset to defaults"
}

# ============================================================================
# Environment Detection
# ============================================================================

# Detect main non-root user
detect_main_user() {
    if [[ -n "${MAIN_USER}" ]]; then
        print_debug "Main user already set: $MAIN_USER"
        return 0
    fi

    print_status "Detecting main user..."

    # Try to detect the main user
    local detected_user=""

    # Method 1: Check SUDO_USER
    if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        detected_user="${SUDO_USER}"
    # Method 2: Check who is logged in on console
    elif [[ -n "$(who | grep -E 'console|tty1' | awk '{print $1}' | grep -v root | head -1)" ]]; then
        detected_user=$(who | grep -E 'console|tty1' | awk '{print $1}' | grep -v root | head -1)
    # Method 3: Check users with home directories
    elif [[ -n "$(ls /home/ 2>/dev/null | head -1)" ]]; then
        detected_user=$(ls /home/ 2>/dev/null | head -1)
    # Method 4: Get user with UID 1000 (common default)
    elif id -u 1000 &>/dev/null; then
        detected_user=$(id -un 1000)
    fi

    if [[ -n "$detected_user" ]] && id "$detected_user" &>/dev/null; then
        MAIN_USER="$detected_user"
        export MAIN_USER
        print_success "Main user detected: $MAIN_USER"
        return 0
    else
        print_warning "Could not detect main user automatically"
        if [[ "$INTERACTIVE_MODE" == true ]]; then
            read -p "Enter the main non-root username: " MAIN_USER
            if id "$MAIN_USER" &>/dev/null; then
                export MAIN_USER
                print_success "Main user set: $MAIN_USER"
                return 0
            else
                print_error "User $MAIN_USER does not exist"
                return 1
            fi
        fi
        return 1
    fi
}

# Export all functions
export -f load_config_file save_config_file prompt_save_config
export -f initialize_configuration show_configuration validate_configuration
export -f reset_configuration detect_main_user

# Source common library if not already loaded
if [ -z "${COMMON_LIB_LOADED:-}" ]; then
    # Use local variable if SCRIPT_DIR is already set
    if [ -z "${SCRIPT_DIR:-}" ]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
    source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || true
    COMMON_LIB_LOADED=true
fi

# Self-test if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Configuration library v${LIB_CONFIG_VERSION} loaded successfully"
    echo ""
    show_configuration
fi
