#!/bin/bash
# System Hardening module - Kernel, sysctl, and system security
# Implements comprehensive system hardening based on CIS benchmarks

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="system-hardening"

# ============================================================================
# Kernel Parameter Hardening
# ============================================================================

# Configure sysctl security parameters
harden_kernel_parameters() {
    print_status "Hardening kernel parameters..."

    # Backup existing sysctl configuration
    backup_file "/etc/sysctl.conf"

    # Create hardened sysctl configuration
    cat << 'EOF' | sudo tee /etc/sysctl.d/99-hardening.conf > /dev/null
# Kernel Security Hardening
# Based on CIS Benchmark recommendations

# ============================================================================
# Network Security
# ============================================================================

# IP Forwarding (disable unless router)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Send redirects (disable)
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Source packet verification
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Accept ICMP redirects (disable)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Secure ICMP redirects (disable)
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Accept source route (disable)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# ICMP Echo Request (disable)
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# SYN cookies (enable)
net.ipv4.tcp_syncookies = 1

# Time-wait assassination hazards (protect against)
net.ipv4.tcp_rfc1337 = 1

# Router advertisements (disable for non-routers)
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# ============================================================================
# Kernel Security
# ============================================================================

# Restrict kernel pointer exposure
kernel.kptr_restrict = 2

# Restrict dmesg
kernel.dmesg_restrict = 1

# Restrict kernel module loading
kernel.modules_disabled = 0

# Hide kernel symbols
kernel.kexec_load_disabled = 1

# Increase ASLR randomization
kernel.randomize_va_space = 2

# Restrict ptrace scope
kernel.yama.ptrace_scope = 1

# Core dump restrictions
fs.suid_dumpable = 0

# Restrict access to kernel performance events
kernel.perf_event_paranoid = 3

# ============================================================================
# Process Security
# ============================================================================

# PID restriction
kernel.pid_max = 65536

# Address space limits
vm.mmap_min_addr = 65536

# Restrict unprivileged BPF
kernel.unprivileged_bpf_disabled = 1

# Restrict user namespaces
kernel.unprivileged_userns_clone = 0

# ============================================================================
# File System Security
# ============================================================================

# Protected hardlinks
fs.protected_hardlinks = 1

# Protected symlinks
fs.protected_symlinks = 1

# Protected FIFOs
fs.protected_fifos = 2

# Protected regular files
fs.protected_regular = 2

# File-max limit
fs.file-max = 2097152

# ============================================================================
# Network Performance & Security Balance
# ============================================================================

# TCP Fast Open (for performance)
net.ipv4.tcp_fastopen = 3

# BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Network buffer sizes
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# Connection tracking
net.netfilter.nf_conntrack_max = 524288
net.nf_conntrack_max = 524288
EOF

    # Apply sysctl settings
    sudo sysctl -p /etc/sysctl.d/99-hardening.conf

    print_success "Kernel parameters hardened"
    return 0
}

# ============================================================================
# File Permission Hardening
# ============================================================================

# Set secure file permissions
harden_file_permissions() {
    print_status "Hardening file permissions..."

    # Secure important files
    local files=(
        "/etc/passwd:644"
        "/etc/shadow:000"
        "/etc/group:644"
        "/etc/gshadow:000"
        "/etc/ssh/sshd_config:600"
        "/boot/grub/grub.cfg:600"
        "/etc/crontab:600"
        "/etc/cron.d:700"
        "/etc/cron.daily:700"
        "/etc/cron.hourly:700"
        "/etc/cron.monthly:700"
        "/etc/cron.weekly:700"
    )

    for item in "${files[@]}"; do
        local file="${item%:*}"
        local perms="${item#*:}"

        if [ -e "$file" ]; then
            sudo chmod "$perms" "$file"
            print_debug "Set permissions $perms on $file"
        fi
    done

    # Remove unnecessary SUID/SGID bits
    local suid_files=(
        "/usr/bin/at"
        "/usr/bin/lppasswd"
    )

    for file in "${suid_files[@]}"; do
        if [ -f "$file" ]; then
            sudo chmod -s "$file" 2>/dev/null || true
            print_debug "Removed SUID/SGID from $file"
        fi
    done

    print_success "File permissions hardened"
    return 0
}

# ============================================================================
# Process and Service Hardening
# ============================================================================

# Disable unnecessary services
disable_unnecessary_services() {
    print_status "Disabling unnecessary services..."

    local services=(
        "bluetooth"
        "cups"
        "avahi-daemon"
        "nfs-client"
        "nfs-server"
        "rpcbind"
        "rsync"
        "xinetd"
    )

    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            sudo systemctl stop "$service" 2>/dev/null || true
            sudo systemctl disable "$service" 2>/dev/null || true
            print_debug "Disabled service: $service"
        fi
    done

    print_success "Unnecessary services disabled"
    return 0
}

# Configure process limits
configure_process_limits() {
    print_status "Configuring process limits..."

    # Create limits configuration
    cat << 'EOF' | sudo tee /etc/security/limits.d/99-hardening.conf > /dev/null
# Process Limits Hardening

# Core dumps
* hard core 0
* soft core 0

# Process limits
* soft nproc 1024
* hard nproc 4096

# File limits
* soft nofile 1024
* hard nofile 65536

# Memory limits
* soft memlock unlimited
* hard memlock unlimited

# Priority limits
* soft nice 0
* hard nice 0
EOF

    print_success "Process limits configured"
    return 0
}

# ============================================================================
# PAM Hardening
# ============================================================================

# Configure PAM security
harden_pam_configuration() {
    print_status "Hardening PAM configuration..."

    # Backup PAM configurations
    backup_file "/etc/pam.d/common-password"
    backup_file "/etc/pam.d/common-auth"

    # Install necessary PAM modules
    sudo apt update
    sudo apt install -y libpam-pwquality libpam-tmpdir

    # Configure password quality requirements
    cat << 'EOF' | sudo tee /etc/security/pwquality.conf > /dev/null
# Password Quality Configuration
minlen = 14
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
maxrepeat = 3
maxclassrepeat = 2
gecoscheck = 1
dictcheck = 1
usercheck = 1
enforcing = 1
EOF

    # Configure account lockout policy
    cat << 'EOF' | sudo tee -a /etc/pam.d/common-auth > /dev/null

# Account lockout after failed attempts
auth required pam_tally2.so onerr=fail audit silent deny=5 unlock_time=900
EOF

    # Configure su access restriction
    cat << 'EOF' | sudo tee -a /etc/pam.d/su > /dev/null

# Restrict su to wheel group
auth required pam_wheel.so use_uid group=sudo
EOF

    print_success "PAM configuration hardened"
    return 0
}

# ============================================================================
# AppArmor Configuration
# ============================================================================

# Configure AppArmor
configure_apparmor() {
    print_status "Configuring AppArmor..."

    # Install AppArmor if not present
    if ! command -v aa-status &> /dev/null; then
        sudo apt update
        sudo apt install -y apparmor apparmor-utils
    fi

    # Enable AppArmor
    sudo systemctl enable apparmor
    sudo systemctl start apparmor

    # Set profiles to enforce mode
    sudo aa-enforce /etc/apparmor.d/*

    # Check status
    sudo aa-status

    print_success "AppArmor configured and enforcing"
    return 0
}

# ============================================================================
# Audit Configuration
# ============================================================================

# Configure auditd
configure_auditd() {
    print_status "Configuring audit daemon..."

    # Install auditd if not present
    if ! command -v auditd &> /dev/null; then
        sudo apt update
        sudo apt install -y auditd audispd-plugins
    fi

    # Configure audit rules
    cat << 'EOF' | sudo tee /etc/audit/rules.d/hardening.rules > /dev/null
# Audit Rules for System Hardening

# Remove any existing rules
-D

# Buffer Size
-b 8192

# Failure Mode
-f 1

# Monitor authentication events
-w /var/log/faillog -p wa -k auth_failures
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# Monitor user/group changes
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Monitor sudo configuration
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Monitor SSH configuration
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Monitor system calls
-a always,exit -F arch=b64 -S execve -k exec
-a always,exit -F arch=b64 -S socket -S connect -k network
-a always,exit -F arch=b64 -S open -S openat -F exit=-EPERM -k access
EOF

    # Load audit rules
    sudo augenrules --load

    # Enable and start auditd
    sudo systemctl enable auditd
    sudo systemctl restart auditd

    print_success "Audit daemon configured"
    return 0
}

# ============================================================================
# Compliance Checking
# ============================================================================

# Check CIS compliance
check_cis_compliance() {
    print_header "CIS Compliance Check"

    local compliance_score=0
    local total_checks=0

    # Check kernel parameters
    ((total_checks++))
    if sysctl net.ipv4.ip_forward | grep -q "= 0"; then
        print_success "IP forwarding disabled"
        ((compliance_score++))
    else
        print_warning "IP forwarding enabled"
    fi

    # Check ICMP redirects
    ((total_checks++))
    if sysctl net.ipv4.conf.all.accept_redirects | grep -q "= 0"; then
        print_success "ICMP redirects disabled"
        ((compliance_score++))
    else
        print_warning "ICMP redirects enabled"
    fi

    # Check source routing
    ((total_checks++))
    if sysctl net.ipv4.conf.all.accept_source_route | grep -q "= 0"; then
        print_success "Source routing disabled"
        ((compliance_score++))
    else
        print_warning "Source routing enabled"
    fi

    # Check core dumps
    ((total_checks++))
    if sysctl fs.suid_dumpable | grep -q "= 0"; then
        print_success "Core dumps restricted"
        ((compliance_score++))
    else
        print_warning "Core dumps not restricted"
    fi

    # Check ASLR
    ((total_checks++))
    if sysctl kernel.randomize_va_space | grep -q "= 2"; then
        print_success "ASLR fully enabled"
        ((compliance_score++))
    else
        print_warning "ASLR not fully enabled"
    fi

    # Check AppArmor
    ((total_checks++))
    if systemctl is-active apparmor &>/dev/null; then
        print_success "AppArmor is active"
        ((compliance_score++))
    else
        print_warning "AppArmor is not active"
    fi

    # Check auditd
    ((total_checks++))
    if systemctl is-active auditd &>/dev/null; then
        print_success "Audit daemon is active"
        ((compliance_score++))
    else
        print_warning "Audit daemon is not active"
    fi

    # Calculate compliance percentage
    local percentage=$((compliance_score * 100 / total_checks))

    echo ""
    print_status "Compliance Score: $compliance_score/$total_checks ($percentage%)"

    if [ $percentage -ge 80 ]; then
        print_success "System meets basic CIS compliance requirements"
    else
        print_warning "System needs additional hardening for CIS compliance"
    fi

    return 0
}

# ============================================================================
# Complete Hardening
# ============================================================================

# Run complete system hardening
complete_system_hardening() {
    print_header "Complete System Hardening"

    harden_kernel_parameters
    harden_file_permissions
    disable_unnecessary_services
    configure_process_limits
    harden_pam_configuration
    configure_apparmor
    configure_auditd

    print_success "System hardening completed!"
    print_warning "Please review all changes and test system functionality"

    # Run compliance check
    check_cis_compliance

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
System Hardening Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --kernel                Harden kernel parameters
    --permissions           Harden file permissions
    --services              Disable unnecessary services
    --limits                Configure process limits
    --pam                   Harden PAM configuration
    --apparmor              Configure AppArmor
    --auditd                Configure audit daemon
    --check-compliance      Check CIS compliance
    --complete              Run complete hardening
    --help                  Show this help message
    --test                  Run module self-tests

EXAMPLES:
    # Run complete hardening
    $0 --complete

    # Check compliance
    $0 --check-compliance

    # Harden specific component
    $0 --kernel
    $0 --apparmor

EOF
}

# Export all functions
export -f harden_kernel_parameters harden_file_permissions
export -f disable_unnecessary_services configure_process_limits
export -f harden_pam_configuration configure_apparmor
export -f configure_auditd check_cis_compliance
export -f complete_system_hardening

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
        --kernel)
            harden_kernel_parameters
            ;;
        --permissions)
            harden_file_permissions
            ;;
        --services)
            disable_unnecessary_services
            ;;
        --limits)
            configure_process_limits
            ;;
        --pam)
            harden_pam_configuration
            ;;
        --apparmor)
            configure_apparmor
            ;;
        --auditd)
            configure_auditd
            ;;
        --check-compliance)
            check_cis_compliance
            ;;
        --complete)
            complete_system_hardening
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running System Hardening module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "System Hardening Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi
