#!/bin/bash
# Backup and restore utilities
# Provides functions for creating backups, restoring files, and emergency rollback

# Library metadata
readonly LIB_BACKUP_VERSION="1.0.0"
readonly LIB_BACKUP_NAME="backup"

# Backup configuration
export BACKUP_DIR="${BACKUP_DIR:-${HOME}/.config-backup-$(date +%Y%m%d-%H%M%S)}"
export BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
export ZERO_TRUST_BACKUP_DIR="${ZERO_TRUST_BACKUP_DIR:-/etc/zero-trust/backups}"

# ============================================================================
# Backup Creation
# ============================================================================

# Create backup directory if it doesn't exist
create_backup() {
    local backup_dir="${1:-$BACKUP_DIR}"

    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
        print_status "Created backup directory: $backup_dir"
        return 0
    fi

    print_debug "Backup directory already exists: $backup_dir"
    return 0
}

# Backup a single file
backup_file() {
    local file="$1"
    local backup_dir="${2:-$BACKUP_DIR}"
    local backup_name="${3:-}"

    if [ ! -f "$file" ]; then
        print_debug "File does not exist, skipping backup: $file"
        return 1
    fi

    create_backup "$backup_dir"

    # Generate backup name if not provided
    if [ -z "$backup_name" ]; then
        backup_name="$(basename "$file").$(date +%Y%m%d-%H%M%S).backup"
    fi

    local backup_path="$backup_dir/$backup_name"

    if cp -p "$file" "$backup_path" 2>/dev/null; then
        print_status "Backed up $file to $backup_path"

        # Set restrictive permissions for security-sensitive files
        if [[ "$file" =~ ssh|key|token|secret|password|config ]]; then
            chmod 600 "$backup_path"
        fi

        return 0
    else
        print_error "Failed to backup $file"
        return 1
    fi
}

# Backup a directory recursively
backup_directory() {
    local dir="$1"
    local backup_dir="${2:-$BACKUP_DIR}"
    local backup_name="${3:-}"

    if [ ! -d "$dir" ]; then
        print_debug "Directory does not exist, skipping backup: $dir"
        return 1
    fi

    create_backup "$backup_dir"

    # Generate backup name if not provided
    if [ -z "$backup_name" ]; then
        backup_name="$(basename "$dir").$(date +%Y%m%d-%H%M%S).tar.gz"
    fi

    local backup_path="$backup_dir/$backup_name"

    print_status "Creating backup of directory $dir..."

    if tar -czf "$backup_path" -C "$(dirname "$dir")" "$(basename "$dir")" 2>/dev/null; then
        print_success "Backed up directory $dir to $backup_path"
        chmod 600 "$backup_path"
        return 0
    else
        print_error "Failed to backup directory $dir"
        return 1
    fi
}

# ============================================================================
# Backup Restoration
# ============================================================================

# Restore a file from backup
restore_file() {
    local backup_file="$1"
    local target_path="$2"

    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi

    # Create target directory if needed
    local target_dir="$(dirname "$target_path")"
    if [ ! -d "$target_dir" ]; then
        mkdir -p "$target_dir"
    fi

    # Backup current file if it exists
    if [ -f "$target_path" ]; then
        backup_file "$target_path" "$BACKUP_DIR" "$(basename "$target_path").before-restore.backup"
    fi

    # Restore the file
    if cp -p "$backup_file" "$target_path" 2>/dev/null; then
        print_success "Restored $backup_file to $target_path"
        return 0
    else
        print_error "Failed to restore $backup_file"
        return 1
    fi
}

# Restore a directory from tar backup
restore_directory() {
    local backup_file="$1"
    local target_dir="${2:-/}"

    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi

    print_status "Restoring directory from $backup_file..."

    if tar -xzf "$backup_file" -C "$target_dir" 2>/dev/null; then
        print_success "Restored directory from $backup_file"
        return 0
    else
        print_error "Failed to restore directory from $backup_file"
        return 1
    fi
}

# ============================================================================
# Backup Management
# ============================================================================

# List all backups
list_backups() {
    local backup_dir="${1:-$BACKUP_DIR}"

    if [ ! -d "$backup_dir" ]; then
        print_warning "No backup directory found at $backup_dir"
        return 1
    fi

    print_header "Available Backups"

    local count=0
    while IFS= read -r backup; do
        local size=$(du -h "$backup" | cut -f1)
        local date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        echo "  $(basename "$backup") - $size - $date"
        ((count++))
    done < <(find "$backup_dir" -type f -name "*.backup" -o -name "*.tar.gz" 2>/dev/null | sort)

    if [ $count -eq 0 ]; then
        echo "  No backups found"
    else
        echo ""
        echo "Total: $count backup(s)"
    fi

    return 0
}

# Clean up old backups
cleanup_old_backups() {
    local backup_dir="${1:-$BACKUP_DIR}"
    local retention_days="${2:-$BACKUP_RETENTION_DAYS}"

    if [ ! -d "$backup_dir" ]; then
        print_debug "No backup directory to clean: $backup_dir"
        return 0
    fi

    print_status "Cleaning up backups older than $retention_days days..."

    local count=0
    while IFS= read -r backup; do
        rm -f "$backup"
        ((count++))
        print_debug "Removed old backup: $(basename "$backup")"
    done < <(find "$backup_dir" -type f \( -name "*.backup" -o -name "*.tar.gz" \) -mtime +$retention_days 2>/dev/null)

    if [ $count -gt 0 ]; then
        print_success "Removed $count old backup(s)"
    else
        print_status "No old backups to remove"
    fi

    return 0
}

# ============================================================================
# System Backup
# ============================================================================

# Create a full system configuration backup
create_system_backup() {
    local backup_name="system-config-$(date +%Y%m%d-%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"

    print_header "Creating System Configuration Backup"

    create_backup "$backup_path"

    # Backup critical system files
    local files_to_backup=(
        "/etc/ssh/sshd_config"
        "/etc/ssh/sshd_config.d"
        "/etc/fstab"
        "/etc/hosts"
        "/etc/hostname"
        "/etc/network/interfaces"
        "/etc/netplan"
        "/etc/systemd/resolved.conf"
        "/etc/security/limits.conf"
        "/etc/sysctl.conf"
        "/etc/sysctl.d"
        "/etc/ufw/ufw.conf"
        "/etc/ufw/user.rules"
        "/etc/ufw/user6.rules"
        "/etc/apparmor.d/local"
        "/etc/audit/auditd.conf"
        "/etc/audit/rules.d"
    )

    for item in "${files_to_backup[@]}"; do
        if [ -f "$item" ]; then
            backup_file "$item" "$backup_path"
        elif [ -d "$item" ]; then
            backup_directory "$item" "$backup_path"
        fi
    done

    # Create backup metadata
    cat > "$backup_path/backup.info" << EOF
Backup Created: $(date)
System: $(hostname)
OS: $(lsb_release -ds 2>/dev/null || echo "Unknown")
Kernel: $(uname -r)
User: $(whoami)
Script Version: ${SCRIPT_VERSION:-Unknown}
EOF

    print_success "System backup created at: $backup_path"
    return 0
}

# ============================================================================
# Emergency Rollback
# ============================================================================

# Perform emergency rollback
emergency_rollback() {
    print_header "Emergency Rollback"
    print_warning "This will restore system configuration from the latest backup"

    if ! confirm_action "Are you sure you want to perform emergency rollback?"; then
        print_status "Rollback cancelled"
        return 1
    fi

    # Find the latest backup directory
    local latest_backup=$(find "$HOME" -maxdepth 1 -type d -name ".config-backup-*" 2>/dev/null | sort -r | head -1)

    if [ -z "$latest_backup" ]; then
        print_error "No backup found for rollback"
        return 1
    fi

    print_status "Using backup: $latest_backup"

    # Restore SSH configuration
    if [ -f "$latest_backup/sshd_config.backup" ]; then
        print_status "Restoring SSH configuration..."
        restore_file "$latest_backup/sshd_config.backup" "/etc/ssh/sshd_config"
        systemctl restart ssh
    fi

    # Restore firewall rules
    if [ -f "$latest_backup/user.rules.backup" ]; then
        print_status "Restoring firewall rules..."
        restore_file "$latest_backup/user.rules.backup" "/etc/ufw/user.rules"
        restore_file "$latest_backup/user6.rules.backup" "/etc/ufw/user6.rules"
        ufw --force reload
    fi

    # Restore other configurations
    for backup in "$latest_backup"/*.backup; do
        if [ -f "$backup" ]; then
            local original_name=$(basename "$backup" | sed 's/\.[0-9]*\.backup$//')
            print_status "Restoring $original_name..."
            # Attempt to restore to common locations
            case "$original_name" in
                sysctl.conf)
                    restore_file "$backup" "/etc/sysctl.conf"
                    sysctl -p
                    ;;
                limits.conf)
                    restore_file "$backup" "/etc/security/limits.conf"
                    ;;
                resolved.conf)
                    restore_file "$backup" "/etc/systemd/resolved.conf"
                    systemctl restart systemd-resolved
                    ;;
            esac
        fi
    done

    print_success "Emergency rollback completed"
    print_warning "Please review system configuration and reboot if necessary"

    return 0
}

# ============================================================================
# Zero Trust Specific Backups
# ============================================================================

# Create Zero Trust configuration backup
create_zero_trust_backup() {
    local backup_dir="$ZERO_TRUST_BACKUP_DIR"
    local backup_name="zero-trust-$(date +%Y%m%d-%H%M%S).tar.gz"

    print_status "Creating Zero Trust configuration backup..."

    # Create backup directory
    sudo mkdir -p "$backup_dir"

    # Create temporary directory for backup
    local temp_dir=$(mktemp -d)

    # Copy Zero Trust configurations
    if [ -d "/etc/zero-trust" ]; then
        cp -r "/etc/zero-trust/configs" "$temp_dir/" 2>/dev/null || true
        cp -r "/etc/zero-trust/docs" "$temp_dir/" 2>/dev/null || true
    fi

    # Backup Docker configurations
    if [ -d "/data/coolify" ]; then
        cp -r "/data/coolify/ssh" "$temp_dir/" 2>/dev/null || true
    fi

    # Create the backup archive
    if tar -czf "$backup_dir/$backup_name" -C "$temp_dir" . 2>/dev/null; then
        chmod 600 "$backup_dir/$backup_name"
        print_success "Zero Trust backup created: $backup_dir/$backup_name"
        rm -rf "$temp_dir"
        return 0
    else
        print_error "Failed to create Zero Trust backup"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Export all functions
export -f create_backup backup_file backup_directory
export -f restore_file restore_directory
export -f list_backups cleanup_old_backups
export -f create_system_backup emergency_rollback
export -f create_zero_trust_backup

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
    echo "Backup library v${LIB_BACKUP_VERSION} loaded successfully"
    echo ""
    echo "Available functions:"
    echo "  - create_backup: Create backup directory"
    echo "  - backup_file: Backup a single file"
    echo "  - backup_directory: Backup a directory"
    echo "  - restore_file: Restore a file from backup"
    echo "  - list_backups: List all available backups"
    echo "  - cleanup_old_backups: Remove old backups"
    echo "  - emergency_rollback: Perform system rollback"
    echo ""

    # Run self-test if requested
    if [[ "${1:-}" == "--test" ]]; then
        echo "Running self-test..."
        test_file="/tmp/backup-test-$$"
        echo "test content" > "$test_file"

        if backup_file "$test_file" "/tmp/backup-test-dir"; then
            echo "✓ Backup test passed"
        else
            echo "✗ Backup test failed"
        fi

        rm -f "$test_file"
        rm -rf "/tmp/backup-test-dir"
    fi
fi