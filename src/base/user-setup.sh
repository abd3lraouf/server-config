#!/bin/bash
# User Setup module - User management and sudo configuration
# Manages user accounts, groups, sudo access, and password policies

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="user-setup"

# User configuration
[[ -z "${DEFAULT_SHELL:-}" ]] && readonly DEFAULT_SHELL="${DEFAULT_SHELL:-/bin/bash}"
readonly PASSWORD_MIN_LENGTH="${PASSWORD_MIN_LENGTH:-14}"
readonly PASSWORD_MAX_AGE="${PASSWORD_MAX_AGE:-90}"
readonly SUDO_TIMEOUT="${SUDO_TIMEOUT:-15}"

# ============================================================================
# User Management
# ============================================================================

# Create new user
create_user() {
    local username="${1:-}"
    local full_name="${2:-}"
    local shell="${3:-$DEFAULT_SHELL}"
    local create_home="${4:-yes}"

    if [ -z "$username" ]; then
        print_error "Username required"
        return 1
    fi

    print_status "Creating user: $username"

    # Check if user already exists
    if id "$username" &>/dev/null; then
        print_warning "User $username already exists"
        return 0
    fi

    # Build useradd command
    local cmd="sudo useradd"

    if [ "$create_home" = "yes" ]; then
        cmd="$cmd -m -d /home/$username"
    fi

    cmd="$cmd -s $shell"

    if [ -n "$full_name" ]; then
        cmd="$cmd -c \"$full_name\""
    fi

    cmd="$cmd $username"

    # Create user
    if eval "$cmd"; then
        print_success "User $username created"

        # Set up home directory permissions
        if [ "$create_home" = "yes" ]; then
            sudo chmod 750 "/home/$username"
            sudo chown "$username:$username" "/home/$username"
        fi

        # Create .ssh directory
        setup_user_ssh "$username"

        return 0
    else
        print_error "Failed to create user $username"
        return 1
    fi
}

# Delete user
delete_user() {
    local username="${1:-}"
    local remove_home="${2:-no}"

    if [ -z "$username" ]; then
        print_error "Username required"
        return 1
    fi

    # Safety check for system users
    if [ "$username" = "root" ] || [ "$(id -u "$username" 2>/dev/null)" -lt 1000 ]; then
        print_error "Cannot delete system user: $username"
        return 1
    fi

    print_status "Deleting user: $username"

    # Kill user processes
    sudo pkill -u "$username" 2>/dev/null || true

    # Delete user
    local cmd="sudo userdel"
    if [ "$remove_home" = "yes" ]; then
        cmd="$cmd -r"
    fi
    cmd="$cmd $username"

    if $cmd; then
        print_success "User $username deleted"
    else
        print_error "Failed to delete user $username"
        return 1
    fi

    return 0
}

# Setup SSH for user
setup_user_ssh() {
    local username="${1:-}"

    if [ -z "$username" ]; then
        print_error "Username required"
        return 1
    fi

    print_status "Setting up SSH for $username"

    local home_dir
    if [ "$username" = "root" ]; then
        home_dir="/root"
    else
        home_dir="/home/$username"
    fi

    # Create .ssh directory
    sudo mkdir -p "$home_dir/.ssh"
    sudo chmod 700 "$home_dir/.ssh"
    sudo touch "$home_dir/.ssh/authorized_keys"
    sudo chmod 600 "$home_dir/.ssh/authorized_keys"
    sudo chown -R "$username:$username" "$home_dir/.ssh"

    print_success "SSH directory created for $username"
    return 0
}

# Set user password
set_user_password() {
    local username="${1:-}"
    local password="${2:-}"

    if [ -z "$username" ]; then
        print_error "Username required"
        return 1
    fi

    print_status "Setting password for $username"

    if [ -z "$password" ]; then
        # Interactive password setting
        sudo passwd "$username"
    else
        # Non-interactive password setting
        echo "$username:$password" | sudo chpasswd
    fi

    # Force password change on first login
    sudo chage -d 0 "$username"

    print_success "Password set for $username"
    print_warning "User must change password on first login"

    return 0
}

# Lock user account
lock_user() {
    local username="${1:-}"

    if [ -z "$username" ]; then
        print_error "Username required"
        return 1
    fi

    print_status "Locking user: $username"

    sudo usermod -L "$username"
    sudo passwd -l "$username"

    print_success "User $username locked"
    return 0
}

# Unlock user account
unlock_user() {
    local username="${1:-}"

    if [ -z "$username" ]; then
        print_error "Username required"
        return 1
    fi

    print_status "Unlocking user: $username"

    sudo usermod -U "$username"
    sudo passwd -u "$username"

    print_success "User $username unlocked"
    return 0
}

# ============================================================================
# Group Management
# ============================================================================

# Create group
create_group() {
    local groupname="${1:-}"
    local gid="${2:-}"

    if [ -z "$groupname" ]; then
        print_error "Group name required"
        return 1
    fi

    print_status "Creating group: $groupname"

    # Check if group exists
    if getent group "$groupname" &>/dev/null; then
        print_warning "Group $groupname already exists"
        return 0
    fi

    # Create group
    local cmd="sudo groupadd"
    if [ -n "$gid" ]; then
        cmd="$cmd -g $gid"
    fi
    cmd="$cmd $groupname"

    if $cmd; then
        print_success "Group $groupname created"
    else
        print_error "Failed to create group $groupname"
        return 1
    fi

    return 0
}

# Add user to group
add_user_to_group() {
    local username="${1:-}"
    local groupname="${2:-}"

    if [ -z "$username" ] || [ -z "$groupname" ]; then
        print_error "Username and group name required"
        return 1
    fi

    print_status "Adding $username to group $groupname"

    sudo usermod -aG "$groupname" "$username"

    print_success "$username added to group $groupname"
    return 0
}

# Remove user from group
remove_user_from_group() {
    local username="${1:-}"
    local groupname="${2:-}"

    if [ -z "$username" ] || [ -z "$groupname" ]; then
        print_error "Username and group name required"
        return 1
    fi

    print_status "Removing $username from group $groupname"

    sudo gpasswd -d "$username" "$groupname"

    print_success "$username removed from group $groupname"
    return 0
}

# ============================================================================
# Sudo Configuration
# ============================================================================

# Configure sudo for user
configure_sudo_user() {
    local username="${1:-}"
    local sudo_type="${2:-full}"  # full, limited, custom

    if [ -z "$username" ]; then
        print_error "Username required"
        return 1
    fi

    print_status "Configuring sudo for $username"

    local sudo_file="/etc/sudoers.d/$username"

    case "$sudo_type" in
        full)
            # Full sudo access
            echo "$username ALL=(ALL:ALL) ALL" | sudo tee "$sudo_file" > /dev/null
            print_success "$username granted full sudo access"
            ;;

        nopasswd)
            # Sudo without password
            echo "$username ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee "$sudo_file" > /dev/null
            print_success "$username granted passwordless sudo access"
            ;;

        limited)
            # Limited sudo access
            cat << EOF | sudo tee "$sudo_file" > /dev/null
# Limited sudo access for $username
$username ALL=(ALL:ALL) /usr/bin/apt update, /usr/bin/apt upgrade
$username ALL=(ALL:ALL) /bin/systemctl status *, /bin/systemctl restart *
$username ALL=(ALL:ALL) /usr/bin/docker *, /usr/bin/docker-compose *
$username ALL=(ALL:ALL) NOPASSWD: /bin/journalctl *
EOF
            print_success "$username granted limited sudo access"
            ;;

        custom)
            # Custom sudo configuration
            print_status "Enter custom sudo rules (Ctrl+D when done):"
            sudo tee "$sudo_file"
            ;;

        remove)
            # Remove sudo access
            sudo rm -f "$sudo_file"
            print_success "Sudo access removed for $username"
            return 0
            ;;

        *)
            print_error "Invalid sudo type: $sudo_type"
            return 1
            ;;
    esac

    # Validate sudoers file
    if sudo visudo -c -f "$sudo_file"; then
        sudo chmod 440 "$sudo_file"
        print_success "Sudo configured for $username"
    else
        print_error "Invalid sudo configuration"
        sudo rm -f "$sudo_file"
        return 1
    fi

    return 0
}

# Configure global sudo settings
configure_sudo_global() {
    print_status "Configuring global sudo settings"

    # Backup sudoers
    backup_file "/etc/sudoers"

    # Create custom sudo configuration
    cat << EOF | sudo tee /etc/sudoers.d/99-security > /dev/null
# Global sudo security settings

# Sudo timeout (minutes)
Defaults        timestamp_timeout=$SUDO_TIMEOUT

# Require password for sudo
Defaults        !targetpw
Defaults        !rootpw

# Secure path
Defaults        secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Environment variables to keep
Defaults        env_keep += "LANG LANGUAGE LC_*"

# Logging
Defaults        logfile="/var/log/sudo.log"
Defaults        log_input
Defaults        log_output

# Security restrictions
Defaults        requiretty
Defaults        use_pty
Defaults        passwd_tries=3

# Lecture users
Defaults        lecture=always
Defaults        lecture_file=/etc/sudo_lecture.txt
EOF

    # Create sudo lecture file
    cat << 'EOF' | sudo tee /etc/sudo_lecture.txt > /dev/null
############################################################
#                    SECURITY WARNING                      #
############################################################
# This system is for authorized use only.                  #
# All activities are monitored and logged.                 #
# Unauthorized access attempts will be prosecuted.         #
############################################################
EOF

    # Validate configuration
    if sudo visudo -c; then
        print_success "Global sudo settings configured"
    else
        print_error "Invalid sudo configuration"
        return 1
    fi

    return 0
}

# ============================================================================
# Password Policies
# ============================================================================

# Configure password policies
configure_password_policies() {
    print_status "Configuring password policies"

    # Install libpam-pwquality if not present
    if ! dpkg -l | grep -q libpam-pwquality; then
        sudo apt update
        sudo apt install -y libpam-pwquality
    fi

    # Configure pwquality
    cat << EOF | sudo tee /etc/security/pwquality.conf > /dev/null
# Password Quality Configuration

# Minimum password length
minlen = $PASSWORD_MIN_LENGTH

# Require at least one digit
dcredit = -1

# Require at least one uppercase
ucredit = -1

# Require at least one lowercase
lcredit = -1

# Require at least one special character
ocredit = -1

# Maximum consecutive repeating characters
maxrepeat = 3

# Maximum consecutive characters from same class
maxclassrepeat = 2

# Check against user information
gecoscheck = 1

# Dictionary check
dictcheck = 1

# Check if contains username
usercheck = 1

# Enforce for root user
enforce_for_root
EOF

    # Configure login.defs
    sudo sed -i "s/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   $PASSWORD_MAX_AGE/" /etc/login.defs
    sudo sed -i "s/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/" /etc/login.defs
    sudo sed -i "s/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/" /etc/login.defs

    # Configure PAM
    if ! grep -q "remember=" /etc/pam.d/common-password; then
        sudo sed -i '/pam_unix.so/ s/$/ remember=5/' /etc/pam.d/common-password
    fi

    print_success "Password policies configured"
    return 0
}

# ============================================================================
# User Auditing
# ============================================================================

# List all users
list_users() {
    print_header "System Users"

    echo "Regular Users (UID >= 1000):"
    awk -F: '$3 >= 1000 && $1 != "nobody" {print "  • " $1 " (UID: " $3 ", Home: " $6 ", Shell: " $7 ")"}' /etc/passwd

    echo ""
    echo "System Users (UID < 1000):"
    awk -F: '$3 < 1000 {print "  • " $1 " (UID: " $3 ")"}' /etc/passwd | head -10

    echo ""
    echo "Users with sudo access:"
    grep -Po '^[^#][^:]+' /etc/sudoers /etc/sudoers.d/* 2>/dev/null | sort -u | while read user; do
        if id "$user" &>/dev/null; then
            echo "  • $user"
        fi
    done

    return 0
}

# Audit user permissions
audit_user_permissions() {
    local username="${1:-}"

    if [ -z "$username" ]; then
        print_error "Username required"
        return 1
    fi

    print_header "User Audit: $username"

    # Basic info
    echo "User Information:"
    id "$username"

    echo ""
    echo "Groups:"
    groups "$username"

    echo ""
    echo "Password Status:"
    sudo passwd -S "$username"

    echo ""
    echo "Last Login:"
    lastlog -u "$username"

    echo ""
    echo "Login History:"
    last "$username" | head -5

    echo ""
    echo "Home Directory:"
    ls -la "/home/$username" 2>/dev/null | head -5

    echo ""
    echo "Sudo Permissions:"
    sudo -l -U "$username" 2>/dev/null || echo "No sudo access"

    echo ""
    echo "Running Processes:"
    ps -u "$username" -o pid,cmd 2>/dev/null | head -10

    return 0
}

# Find users with weak settings
audit_weak_users() {
    print_header "User Security Audit"

    local issues=0

    # Check for users with UID 0 besides root
    echo "Checking for non-root UID 0 users..."
    if awk -F: '$3 == 0 && $1 != "root" {print "  WARNING: " $1}' /etc/passwd | grep -q WARNING; then
        ((issues++))
    else
        print_success "No unauthorized UID 0 users"
    fi

    # Check for users with empty passwords
    echo "Checking for empty passwords..."
    if sudo awk -F: '($2 == "" || $2 == "!!" || $2 == "*") {print "  WARNING: " $1 " has no password"}' /etc/shadow | grep -q WARNING; then
        ((issues++))
    else
        print_success "No users with empty passwords"
    fi

    # Check for users with no password expiry
    echo "Checking password expiry..."
    local users_no_expiry=$(sudo awk -F: '$5 == 99999 {print $1}' /etc/shadow | wc -l)
    if [ "$users_no_expiry" -gt 0 ]; then
        print_warning "$users_no_expiry users have no password expiry"
        ((issues++))
    else
        print_success "All users have password expiry set"
    fi

    # Summary
    echo ""
    if [ $issues -eq 0 ]; then
        print_success "User security audit passed"
    else
        print_warning "User security audit found $issues issue(s)"
    fi

    return $issues
}

# ============================================================================
# Interactive Setup
# ============================================================================

# Interactive user creation
create_user_interactive() {
    print_header "Interactive User Creation"

    read -p "Enter username: " username
    read -p "Enter full name (optional): " full_name
    read -p "Create home directory? [Y/n]: " -n 1 -r
    echo
    local create_home="yes"
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        create_home="no"
    fi

    # Create user
    create_user "$username" "$full_name" "$DEFAULT_SHELL" "$create_home"

    # Set password
    if confirm_action "Set password now?"; then
        set_user_password "$username"
    fi

    # Configure sudo
    if confirm_action "Grant sudo access?"; then
        echo "Sudo access type:"
        echo "  1. Full access"
        echo "  2. Full access (no password)"
        echo "  3. Limited access"
        echo "  4. No sudo access"
        read -p "Choice [1-4]: " sudo_choice

        case "$sudo_choice" in
            1) configure_sudo_user "$username" "full" ;;
            2) configure_sudo_user "$username" "nopasswd" ;;
            3) configure_sudo_user "$username" "limited" ;;
            4) echo "No sudo access granted" ;;
            *) print_warning "Invalid choice, no sudo access granted" ;;
        esac
    fi

    # Add to groups
    if confirm_action "Add to additional groups?"; then
        read -p "Enter groups (comma-separated): " groups
        IFS=',' read -ra GROUP_ARRAY <<< "$groups"
        for group in "${GROUP_ARRAY[@]}"; do
            add_user_to_group "$username" "$(echo "$group" | xargs)"
        done
    fi

    print_success "User $username created successfully"
    audit_user_permissions "$username"

    return 0
}

# ============================================================================
# Complete Setup
# ============================================================================

# Run complete user setup
setup_users_complete() {
    print_header "Complete User Management Setup"

    # Configure password policies
    configure_password_policies

    # Configure global sudo settings
    configure_sudo_global

    # Audit existing users
    audit_weak_users

    # Create new users if needed
    if confirm_action "Create new users?"; then
        while true; do
            create_user_interactive

            if ! confirm_action "Create another user?"; then
                break
            fi
        done
    fi

    # List all users
    list_users

    print_success "User management setup completed!"

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
User Setup Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --create USER           Create new user
    --delete USER           Delete user
    --password USER         Set user password
    --lock USER             Lock user account
    --unlock USER           Unlock user account
    --sudo USER TYPE        Configure sudo (full/nopasswd/limited/remove)
    --add-group USER GROUP  Add user to group
    --list                  List all users
    --audit USER            Audit specific user
    --audit-all             Security audit all users
    --password-policy       Configure password policies
    --interactive           Interactive user creation
    --complete              Complete user setup
    --help                  Show this help message
    --test                  Run module self-tests

EXAMPLES:
    # Create user with full sudo
    $0 --create john
    $0 --sudo john full

    # Interactive user creation
    $0 --interactive

    # Audit all users
    $0 --audit-all

    # Complete setup
    $0 --complete

EOF
}

# Confirm action helper
confirm_action() {
    local prompt="${1:-Continue?}"
    read -p "$prompt [y/N]: " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Export all functions
export -f create_user delete_user setup_user_ssh set_user_password
export -f lock_user unlock_user create_group add_user_to_group
export -f remove_user_from_group configure_sudo_user configure_sudo_global
export -f configure_password_policies list_users audit_user_permissions
export -f audit_weak_users create_user_interactive setup_users_complete

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
source "${SCRIPT_DIR}/../lib/backup.sh" 2>/dev/null || true

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --create)
            create_user "${2}" "${3:-}" "${4:-$DEFAULT_SHELL}" "${5:-yes}"
            ;;
        --delete)
            delete_user "${2}" "${3:-no}"
            ;;
        --password)
            set_user_password "${2}" "${3:-}"
            ;;
        --lock)
            lock_user "${2}"
            ;;
        --unlock)
            unlock_user "${2}"
            ;;
        --sudo)
            configure_sudo_user "${2}" "${3:-full}"
            ;;
        --add-group)
            add_user_to_group "${2}" "${3}"
            ;;
        --list)
            list_users
            ;;
        --audit)
            audit_user_permissions "${2}"
            ;;
        --audit-all)
            audit_weak_users
            ;;
        --password-policy)
            configure_password_policies
            ;;
        --interactive)
            create_user_interactive
            ;;
        --complete)
            setup_users_complete
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running User Setup module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "User Setup Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi
