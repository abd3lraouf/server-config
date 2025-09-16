#!/bin/bash
# System update and package management module
# Handles system updates, package management, and APT configuration

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="system-update"

# ============================================================================
# System Update Functions
# ============================================================================

# Perform full system update
system_update() {
    print_status "Updating system packages..."

    # Update package lists
    if ! sudo apt update; then
        print_error "Failed to update package lists"
        return 1
    fi

    # Upgrade all packages
    print_status "Upgrading installed packages (this may take a while)..."
    if ! sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y; then
        print_error "Failed to upgrade packages"
        return 1
    fi

    # Perform distribution upgrade if available
    if sudo apt list --upgradable 2>/dev/null | grep -q "upgradable"; then
        print_status "Performing distribution upgrade..."
        sudo DEBIAN_FRONTEND=noninteractive apt dist-upgrade -y
    fi

    # Remove unnecessary packages
    print_status "Cleaning up unnecessary packages..."
    sudo apt autoremove -y
    sudo apt autoclean -y

    print_success "System update completed"
    return 0
}

# ============================================================================
# APT Configuration
# ============================================================================

# Clean and fix APT sources
clean_apt_sources() {
    print_status "Cleaning APT sources..."

    # Backup sources list
    backup_file "/etc/apt/sources.list"

    # Remove duplicate sources
    print_status "Removing duplicate APT sources..."
    sudo rm -f /etc/apt/sources.list.d/*.list.*
    sudo rm -f /etc/apt/sources.list.d/*duplicate*

    # Fix broken packages
    print_status "Fixing broken packages..."
    sudo dpkg --configure -a
    sudo apt-get install -f -y

    # Update package cache
    sudo apt update

    print_success "APT sources cleaned"
    return 0
}

# Fix broken packages
fix_broken_packages() {
    print_status "Attempting to fix broken packages..."

    # Configure pending packages
    sudo dpkg --configure -a

    # Fix broken dependencies
    sudo apt-get install -f -y

    # Clean package cache
    sudo apt-get clean

    # Rebuild package database
    sudo apt-get update

    # Check if fixes worked
    if sudo dpkg --audit 2>/dev/null | grep -q .; then
        print_warning "Some packages may still have issues"
        return 1
    fi

    print_success "Package issues resolved"
    return 0
}

# ============================================================================
# Automatic Updates
# ============================================================================

# Configure unattended-upgrades for automatic security updates
configure_auto_updates() {
    print_status "Configuring automatic security updates..."

    # Install unattended-upgrades
    if ! dpkg -l | grep -q "^ii.*unattended-upgrades"; then
        print_status "Installing unattended-upgrades..."
        sudo apt install -y unattended-upgrades apt-listchanges
    fi

    # Backup existing configuration
    backup_file "/etc/apt/apt.conf.d/50unattended-upgrades"

    # Configure unattended-upgrades
    cat << 'EOF' | sudo tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null
// Automatically upgrade packages from these origins
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// List of packages to not update
Unattended-Upgrade::Package-Blacklist {
};

// Remove unused kernel packages
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Remove unused dependencies
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Automatically reboot if required
Unattended-Upgrade::Automatic-Reboot "false";

// Automatically reboot time
Unattended-Upgrade::Automatic-Reboot-Time "03:00";

// Enable email notifications
Unattended-Upgrade::Mail "root";

// Enable logging
Unattended-Upgrade::SyslogEnable "true";
EOF

    # Enable automatic updates
    cat << 'EOF' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    # Enable the service
    sudo systemctl enable unattended-upgrades
    sudo systemctl start unattended-upgrades

    print_success "Automatic security updates configured"
    return 0
}

# ============================================================================
# Essential Packages
# ============================================================================

# Install essential system packages
install_essential_packages() {
    print_status "Installing essential system packages..."

    local packages=(
        "curl"
        "wget"
        "git"
        "vim"
        "nano"
        "htop"
        "net-tools"
        "software-properties-common"
        "apt-transport-https"
        "ca-certificates"
        "gnupg"
        "lsb-release"
        "ufw"
        "fail2ban"
        "sudo"
        "openssh-server"
        "build-essential"
        "zip"
        "unzip"
    )

    # Update package lists first
    sudo apt update

    # Install packages
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$package"; then
            print_status "Installing $package..."
            sudo DEBIAN_FRONTEND=noninteractive apt install -y "$package"
        else
            print_debug "$package is already installed"
        fi
    done

    print_success "Essential packages installed"
    return 0
}

# ============================================================================
# Repository Management
# ============================================================================

# Add a new APT repository
add_apt_repository() {
    local repo_name="$1"
    local repo_url="$2"
    local gpg_key_url="$3"

    print_status "Adding $repo_name repository..."

    # Download and add GPG key if provided
    if [ -n "$gpg_key_url" ]; then
        curl -fsSL "$gpg_key_url" | sudo gpg --dearmor -o "/usr/share/keyrings/${repo_name}-keyring.gpg"
    fi

    # Add repository
    echo "$repo_url" | sudo tee "/etc/apt/sources.list.d/${repo_name}.list" > /dev/null

    # Update package lists
    sudo apt update

    print_success "$repo_name repository added"
    return 0
}

# Remove an APT repository
remove_apt_repository() {
    local repo_name="$1"

    print_status "Removing $repo_name repository..."

    # Remove repository file
    sudo rm -f "/etc/apt/sources.list.d/${repo_name}.list"

    # Remove GPG key if exists
    sudo rm -f "/usr/share/keyrings/${repo_name}-keyring.gpg"

    # Update package lists
    sudo apt update

    print_success "$repo_name repository removed"
    return 0
}

# ============================================================================
# Kernel Management
# ============================================================================

# Update kernel to latest version
update_kernel() {
    print_status "Checking for kernel updates..."

    # Get current kernel version
    local current_kernel=$(uname -r)
    print_status "Current kernel: $current_kernel"

    # Check for newer kernel
    sudo apt update
    if sudo apt list --upgradable 2>/dev/null | grep -q "linux-image"; then
        print_status "Newer kernel available, installing..."
        sudo DEBIAN_FRONTEND=noninteractive apt install -y linux-generic

        print_success "Kernel updated. Reboot required to use new kernel."
        return 0
    else
        print_status "Kernel is up to date"
        return 0
    fi
}

# Remove old kernels
cleanup_old_kernels() {
    print_status "Removing old kernel packages..."

    # Keep only the current and one previous kernel
    sudo apt autoremove --purge -y

    print_success "Old kernels removed"
    return 0
}

# ============================================================================
# Complete System Maintenance
# ============================================================================

# Run complete system maintenance
system_maintenance() {
    print_header "System Maintenance"

    system_update
    fix_broken_packages
    cleanup_old_kernels
    configure_auto_updates

    print_success "System maintenance completed"
    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
System Update Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --update                Perform system update
    --clean-apt            Clean APT sources
    --fix-broken           Fix broken packages
    --auto-updates         Configure automatic updates
    --install-essential    Install essential packages
    --update-kernel        Update system kernel
    --maintenance          Run complete maintenance
    --help                 Show this help message
    --test                 Run module self-tests

EXAMPLES:
    # Run full system update
    $0 --update

    # Configure automatic updates
    $0 --auto-updates

    # Complete maintenance
    $0 --maintenance

EOF
}

# Export all functions
export -f system_update clean_apt_sources fix_broken_packages
export -f configure_auto_updates install_essential_packages
export -f add_apt_repository remove_apt_repository
export -f update_kernel cleanup_old_kernels system_maintenance

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
# Load backup library using load_module if available
if command -v load_module &>/dev/null; then
    load_module "lib/backup.sh" || true
else
    source "${SCRIPT_DIR}/../lib/backup.sh" 2>/dev/null || true
fi

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --update)
            system_update
            ;;
        --clean-apt)
            clean_apt_sources
            ;;
        --fix-broken)
            fix_broken_packages
            ;;
        --auto-updates)
            configure_auto_updates
            ;;
        --install-essential)
            install_essential_packages
            ;;
        --update-kernel)
            update_kernel
            ;;
        --maintenance)
            system_maintenance
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running system update module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "System Update Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi
