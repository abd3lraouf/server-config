#!/bin/bash
# Common utilities and functions used across all modules
# This library provides core functionality for logging, output formatting, and error handling

# Script metadata
readonly LIB_VERSION="1.0.0"
readonly LIB_NAME="common"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Export colors for use in other scripts
export RED GREEN YELLOW BLUE MAGENTA CYAN NC

# Global configuration
# Don't export SCRIPT_VERSION if it's already set
[[ -z "${SCRIPT_VERSION:-}" ]] && export SCRIPT_VERSION="2.0.0"
export LOG_FILE="${LOG_FILE:-/var/log/zero-trust-setup-$(date +%Y%m%d-%H%M%S).log}"
export BACKUP_DIR="${BACKUP_DIR:-${HOME}/.config-backup-$(date +%Y%m%d-%H%M%S)}"
export VERBOSE="${VERBOSE:-false}"
export DRY_RUN="${DRY_RUN:-false}"
export DEBUG="${DEBUG:-0}"

# Enable debug mode if DEBUG environment variable is set
[[ "${DEBUG}" == "1" ]] && set -x

# ============================================================================
# Logging Functions
# ============================================================================

# Enhanced logging function with file output
log_message() {
    local level="$1"
    local message="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Write to log file only if we have write permissions
    if [[ -w "$LOG_FILE" ]] || [[ "$EUID" -eq 0 ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi

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
    return 0  # Always return success
}

# Convenience logging functions
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

# ============================================================================
# Error Handling
# ============================================================================

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
    # Cleanup tasks can be added by sourcing scripts
}

# Setup error trapping
setup_error_trap() {
    trap 'error_handler $? $LINENO' ERR
}

# ============================================================================
# Logging Initialization
# ============================================================================

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

# ============================================================================
# Utility Functions
# ============================================================================

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run with sudo"
        print_status "Usage: sudo $0 [options]"
        exit 1
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Get the correct SSH service name
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

# Get the correct docker compose command
get_docker_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null 2>&1; then
        echo "docker compose"
    else
        echo ""
    fi
}

# Ensure Docker network exists
ensure_docker_network() {
    local network_name="${1:-internal}"

    if ! sudo docker network ls --format '{{.Name}}' | grep -q "^${network_name}$"; then
        print_status "Creating Docker network: $network_name..."
        if sudo docker network create "$network_name" >/dev/null 2>&1; then
            print_success "Docker network '$network_name' created"
            return 0
        else
            print_error "Failed to create Docker network '$network_name'"
            return 1
        fi
    else
        print_status "Docker network '$network_name' already exists"
        return 0
    fi
}

# Display a separator line
print_separator() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

# Display a header
print_header() {
    local title="$1"
    print_separator
    echo -e "${CYAN}     ${title}${NC}"
    print_separator
}

# Prompt for user confirmation
confirm_action() {
    local prompt="${1:-Continue?}"
    local response

    if [[ "${DRY_RUN}" == true ]]; then
        print_warning "DRY RUN: Would prompt: $prompt"
        return 0
    fi

    echo -ne "${YELLOW}${prompt} [y/N]: ${NC}"
    read -r response

    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Get system information
get_system_info() {
    local os_name=$(lsb_release -si 2>/dev/null || echo "Unknown")
    local os_version=$(lsb_release -sr 2>/dev/null || echo "Unknown")
    local kernel_version=$(uname -r)
    local hostname=$(hostname)

    echo "OS: $os_name $os_version"
    echo "Kernel: $kernel_version"
    echo "Hostname: $hostname"
}

# Check if running in a container
is_container() {
    if [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]]; then
        return 0
    fi

    if grep -q 'docker\|lxc\|containerd' /proc/1/cgroup 2>/dev/null; then
        return 0
    fi

    return 1
}

# Check if running in WSL
is_wsl() {
    if grep -qi microsoft /proc/version 2>/dev/null; then
        return 0
    fi
    return 1
}

# Export all functions for use in other scripts
export -f log_message print_status print_success print_error print_warning print_debug
export -f error_handler cleanup_on_error setup_error_trap initialize_logging
export -f check_root command_exists get_ssh_service_name get_docker_compose_cmd
export -f ensure_docker_network print_separator print_header confirm_action
export -f get_system_info is_container is_wsl

# Initialize logging if this is the main script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Common library v${LIB_VERSION} loaded successfully"
    echo "This library provides shared utilities for the Zero Trust setup scripts"
fi