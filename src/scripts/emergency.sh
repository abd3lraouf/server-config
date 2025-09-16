#!/bin/bash
# Emergency Recovery module - System recovery and rollback procedures
# Provides emergency recovery, system restore, and troubleshooting tools

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="emergency-recovery"

# Recovery configuration
readonly RECOVERY_LOG="/var/log/emergency-recovery.log"
readonly RECOVERY_BACKUP_DIR="/root/emergency-backups"
readonly RECOVERY_MODE_FLAG="/tmp/.emergency_recovery_mode"

# ============================================================================
# Emergency Mode Detection
# ============================================================================

# Check if system is in emergency state
check_emergency_state() {
    local emergency=false
    local issues=()

    print_header "System Emergency Check"

    # Check if SSH is accessible
    if ! systemctl is-active sshd &>/dev/null; then
        issues+=("SSH service is down")
        emergency=true
    fi

    # Check if network is up
    if ! ping -c 1 -W 2 google.com &>/dev/null && ! ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
        issues+=("Network connectivity lost")
        emergency=true
    fi

    # Check disk space
    local disk_usage=$(df / | awk 'NR==2 {print int($5)}')
    if [ "$disk_usage" -gt 95 ]; then
        issues+=("Critical disk space (${disk_usage}% used)")
        emergency=true
    fi

    # Check system load
    local load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print int($1)}')
    local cpu_count=$(nproc)
    if [ "$load" -gt $((cpu_count * 4)) ]; then
        issues+=("System overload (load: $load)")
        emergency=true
    fi

    # Check for kernel panic signs
    if dmesg | tail -100 | grep -q "kernel panic\|OOM\|Out of memory"; then
        issues+=("Kernel issues detected")
        emergency=true
    fi

    # Check firewall
    if command -v ufw &>/dev/null && ! sudo ufw status | grep -q "Status: active"; then
        issues+=("Firewall is not active")
        emergency=true
    fi

    # Report findings
    if [ "$emergency" = true ]; then
        print_error "System is in emergency state!"
        echo "Issues detected:"
        for issue in "${issues[@]}"; do
            echo "  • $issue"
        done
        return 1
    else
        print_success "No emergency conditions detected"
        return 0
    fi
}

# ============================================================================
# SSH Recovery
# ============================================================================

# Recover SSH access
recover_ssh() {
    print_header "SSH Recovery"

    # Backup current SSH config
    backup_file "/etc/ssh/sshd_config"

    # Create minimal working SSH config
    print_status "Creating emergency SSH configuration..."
    cat << 'EOF' | sudo tee /etc/ssh/sshd_config.d/99-emergency.conf > /dev/null
# Emergency SSH Configuration
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

    # Restart SSH service
    print_status "Restarting SSH service..."
    sudo systemctl restart sshd

    if systemctl is-active sshd &>/dev/null; then
        print_success "SSH service recovered"

        # Set temporary root password if needed
        if confirm_action "Set temporary root password for emergency access?"; then
            sudo passwd root
            print_warning "Remember to disable root password login after recovery!"
        fi
    else
        print_error "Failed to recover SSH service"

        # Try alternative SSH restart methods
        print_status "Trying alternative SSH restart..."
        sudo service ssh restart || sudo /etc/init.d/ssh restart
    fi

    return 0
}

# ============================================================================
# Network Recovery
# ============================================================================

# Recover network connectivity
recover_network() {
    print_header "Network Recovery"

    # Reset network interfaces
    print_status "Resetting network interfaces..."

    # Get primary interface
    local primary_interface=$(ip route | grep default | awk '{print $5}' | head -1)

    if [ -z "$primary_interface" ]; then
        primary_interface="eth0"
        print_warning "Could not detect primary interface, using eth0"
    fi

    # Bring interface down and up
    sudo ip link set "$primary_interface" down
    sleep 2
    sudo ip link set "$primary_interface" up

    # Restart networking service
    print_status "Restarting networking services..."
    sudo systemctl restart systemd-networkd
    sudo systemctl restart NetworkManager 2>/dev/null || true

    # Request new DHCP lease
    print_status "Requesting new DHCP lease..."
    sudo dhclient -r "$primary_interface"
    sudo dhclient "$primary_interface"

    # Test connectivity
    print_status "Testing network connectivity..."
    if ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
        print_success "Network connectivity restored"
    else
        print_warning "Network still not responding, checking DNS..."

        # Reset DNS
        echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
        echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf

        if ping -c 1 -W 2 google.com &>/dev/null; then
            print_success "Network recovered with DNS fix"
        else
            print_error "Network recovery failed"
        fi
    fi

    return 0
}

# ============================================================================
# Firewall Recovery
# ============================================================================

# Recover firewall to safe state
recover_firewall() {
    print_header "Firewall Recovery"

    if ! command -v ufw &>/dev/null; then
        print_warning "UFW not installed"
        return 1
    fi

    # Backup current rules
    print_status "Backing up current firewall rules..."
    sudo ufw status numbered > "$RECOVERY_BACKUP_DIR/ufw-rules-$(date +%Y%m%d-%H%M%S).txt"

    # Reset to safe defaults
    print_status "Resetting firewall to safe defaults..."

    # Disable firewall temporarily
    sudo ufw --force disable

    # Reset rules
    echo "y" | sudo ufw --force reset

    # Apply minimal safe rules
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # Allow SSH (critical)
    sudo ufw allow 22/tcp comment 'SSH Emergency'

    # Allow HTTP/HTTPS if web server present
    if systemctl is-active nginx &>/dev/null || systemctl is-active apache2 &>/dev/null; then
        sudo ufw allow 80/tcp comment 'HTTP'
        sudo ufw allow 443/tcp comment 'HTTPS'
    fi

    # Enable firewall
    echo "y" | sudo ufw --force enable

    print_success "Firewall recovered with minimal rules"
    sudo ufw status

    return 0
}

# ============================================================================
# Service Recovery
# ============================================================================

# Recover failed services
recover_services() {
    print_header "Service Recovery"

    # Get list of failed services
    local failed_services=$(systemctl list-units --failed --no-legend | awk '{print $1}')

    if [ -z "$failed_services" ]; then
        print_success "No failed services found"
        return 0
    fi

    echo "Failed services detected:"
    echo "$failed_services"
    echo ""

    for service in $failed_services; do
        print_status "Attempting to recover: $service"

        # Reset failed state
        sudo systemctl reset-failed "$service"

        # Try to restart
        if sudo systemctl restart "$service" 2>/dev/null; then
            print_success "$service recovered"
        else
            print_warning "$service recovery failed, checking logs..."
            sudo journalctl -u "$service" -n 5 --no-pager
        fi
    done

    return 0
}

# ============================================================================
# Disk Space Recovery
# ============================================================================

# Recover disk space
recover_disk_space() {
    print_header "Disk Space Recovery"

    local initial_usage=$(df / | awk 'NR==2 {print int($5)}')
    print_status "Current disk usage: ${initial_usage}%"

    # Clean package cache
    print_status "Cleaning package cache..."
    sudo apt clean
    sudo apt autoremove -y

    # Clean old kernels
    print_status "Removing old kernels..."
    sudo apt autoremove --purge -y

    # Clean logs
    print_status "Cleaning old logs..."
    sudo journalctl --vacuum-time=3d
    sudo find /var/log -type f -name "*.log" -mtime +7 -delete 2>/dev/null
    sudo find /var/log -type f -name "*.gz" -mtime +7 -delete 2>/dev/null

    # Clean Docker if present
    if command -v docker &>/dev/null; then
        print_status "Cleaning Docker resources..."
        docker system prune -af --volumes 2>/dev/null || true
    fi

    # Clean temp files
    print_status "Cleaning temporary files..."
    sudo rm -rf /tmp/*
    sudo rm -rf /var/tmp/*

    # Show results
    local final_usage=$(df / | awk 'NR==2 {print int($5)}')
    local recovered=$((initial_usage - final_usage))

    print_success "Disk space recovered: ${recovered}%"
    print_status "Final disk usage: ${final_usage}%"

    df -h /

    return 0
}

# ============================================================================
# System Rollback
# ============================================================================

# Rollback system configurations
rollback_system() {
    print_header "System Configuration Rollback"

    # Find available backups
    local backup_dirs=($(ls -dt /root/*backup* 2>/dev/null | head -5))

    if [ ${#backup_dirs[@]} -eq 0 ]; then
        print_error "No backup directories found"
        return 1
    fi

    echo "Available backups:"
    for i in "${!backup_dirs[@]}"; do
        echo "  $((i+1)). ${backup_dirs[$i]}"
    done

    read -p "Select backup to restore (1-${#backup_dirs[@]}): " choice

    if [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backup_dirs[@]} ]; then
        print_error "Invalid selection"
        return 1
    fi

    local backup_dir="${backup_dirs[$((choice-1))]}"
    print_status "Restoring from: $backup_dir"

    # Restore configurations
    if [ -d "$backup_dir" ]; then
        # SSH config
        if [ -f "$backup_dir/sshd_config" ]; then
            sudo cp "$backup_dir/sshd_config" /etc/ssh/sshd_config
            sudo systemctl restart sshd
            print_success "SSH configuration restored"
        fi

        # Firewall rules
        if [ -f "$backup_dir/ufw-rules.txt" ]; then
            # Parse and restore UFW rules
            print_warning "Manual firewall restoration may be required"
        fi

        # Other configs
        for config in "$backup_dir"/*; do
            local basename=$(basename "$config")
            print_status "Found backup: $basename"
        done
    fi

    print_success "Rollback completed"
    return 0
}

# ============================================================================
# Safe Mode Boot
# ============================================================================

# Enter safe mode
enter_safe_mode() {
    print_header "Entering Safe Mode"

    # Create safe mode flag
    touch "$RECOVERY_MODE_FLAG"

    # Disable non-essential services
    print_status "Disabling non-essential services..."

    local non_essential=(
        "docker"
        "containerd"
        "crowdsec"
        "traefik"
        "netdata"
        "nginx"
        "apache2"
    )

    for service in "${non_essential[@]}"; do
        if systemctl is-enabled "$service" &>/dev/null; then
            sudo systemctl stop "$service"
            print_status "Stopped: $service"
        fi
    done

    # Set minimal firewall
    recover_firewall

    # Ensure SSH is running
    sudo systemctl start sshd

    print_success "System is now in safe mode"
    print_warning "Only essential services are running"

    return 0
}

# Exit safe mode
exit_safe_mode() {
    print_header "Exiting Safe Mode"

    if [ ! -f "$RECOVERY_MODE_FLAG" ]; then
        print_warning "System is not in safe mode"
        return 1
    fi

    # Remove safe mode flag
    rm -f "$RECOVERY_MODE_FLAG"

    # Restart all services
    print_status "Restarting all services..."
    sudo systemctl daemon-reload
    sudo systemctl restart multi-user.target

    print_success "Exited safe mode"
    return 0
}

# ============================================================================
# Diagnostic Tools
# ============================================================================

# Run system diagnostics
run_diagnostics() {
    print_header "System Diagnostics"

    local report_file="$RECOVERY_BACKUP_DIR/diagnostics-$(date +%Y%m%d-%H%M%S).txt"

    {
        echo "System Diagnostics Report"
        echo "========================="
        echo "Date: $(date)"
        echo "Hostname: $(hostname -f)"
        echo ""

        echo "System Information:"
        uname -a
        echo ""

        echo "Uptime and Load:"
        uptime
        echo ""

        echo "Memory Usage:"
        free -h
        echo ""

        echo "Disk Usage:"
        df -h
        echo ""

        echo "Network Interfaces:"
        ip addr
        echo ""

        echo "Failed Services:"
        systemctl list-units --failed
        echo ""

        echo "Recent System Errors:"
        sudo journalctl -p err -n 50 --no-pager
        echo ""

        echo "Firewall Status:"
        sudo ufw status verbose
        echo ""

        echo "Active Connections:"
        ss -tulpn
        echo ""

        echo "Top Processes:"
        ps aux | head -20

    } | tee "$report_file"

    print_success "Diagnostics saved to: $report_file"
    return 0
}

# ============================================================================
# Complete Recovery
# ============================================================================

# Run complete emergency recovery
run_emergency_recovery() {
    print_header "Emergency Recovery Procedure"

    # Create recovery backup directory
    sudo mkdir -p "$RECOVERY_BACKUP_DIR"

    # Check emergency state
    check_emergency_state

    # Menu for recovery options
    echo "Select recovery action:"
    echo "  1. Recover SSH access"
    echo "  2. Recover network connectivity"
    echo "  3. Recover firewall"
    echo "  4. Recover failed services"
    echo "  5. Recover disk space"
    echo "  6. System rollback"
    echo "  7. Enter safe mode"
    echo "  8. Run diagnostics"
    echo "  9. Complete recovery (all)"
    echo "  0. Exit"

    read -p "Choice [0-9]: " choice

    case "$choice" in
        1) recover_ssh ;;
        2) recover_network ;;
        3) recover_firewall ;;
        4) recover_services ;;
        5) recover_disk_space ;;
        6) rollback_system ;;
        7) enter_safe_mode ;;
        8) run_diagnostics ;;
        9)
            recover_ssh
            recover_network
            recover_firewall
            recover_services
            recover_disk_space
            run_diagnostics
            ;;
        0) exit 0 ;;
        *) print_error "Invalid choice" ;;
    esac

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Emergency Recovery Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --check                 Check system emergency state
    --recover-ssh           Recover SSH access
    --recover-network       Recover network connectivity
    --recover-firewall      Recover firewall to safe state
    --recover-services      Recover failed services
    --recover-disk          Recover disk space
    --rollback              Rollback system configurations
    --safe-mode             Enter safe mode
    --exit-safe-mode        Exit safe mode
    --diagnostics           Run system diagnostics
    --interactive           Interactive recovery menu
    --help                  Show this help message

EXAMPLES:
    # Check emergency state
    $0 --check

    # Recover SSH
    $0 --recover-ssh

    # Enter safe mode
    $0 --safe-mode

    # Run diagnostics
    $0 --diagnostics

    # Interactive recovery
    $0 --interactive

WARNING: This module performs emergency recovery operations.
         Use with caution and ensure you have backups.

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
export -f check_emergency_state
export -f recover_ssh recover_network recover_firewall
export -f recover_services recover_disk_space
export -f rollback_system enter_safe_mode exit_safe_mode
export -f run_diagnostics run_emergency_recovery

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
    # Log all recovery actions
    exec 2>&1 | tee -a "$RECOVERY_LOG"

    case "${1:-}" in
        --check)
            check_emergency_state
            ;;
        --recover-ssh)
            recover_ssh
            ;;
        --recover-network)
            recover_network
            ;;
        --recover-firewall)
            recover_firewall
            ;;
        --recover-services)
            recover_services
            ;;
        --recover-disk)
            recover_disk_space
            ;;
        --rollback)
            rollback_system
            ;;
        --safe-mode)
            enter_safe_mode
            ;;
        --exit-safe-mode)
            exit_safe_mode
            ;;
        --diagnostics)
            run_diagnostics
            ;;
        --interactive)
            run_emergency_recovery
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Emergency Recovery Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            echo ""
            echo "Quick check: $0 --check"
            ;;
    esac
fi
