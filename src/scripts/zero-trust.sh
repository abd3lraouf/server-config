#!/bin/bash
# Zero Trust Complete Orchestration Script
# Coordinates all security modules for complete Zero Trust setup

# Script metadata
readonly MODULE_VERSION="1.0.0"
readonly MODULE_NAME="zero-trust-orchestrator"

# Configuration
readonly ZERO_TRUST_LOG="/var/log/zero-trust-setup.log"
readonly ZERO_TRUST_BACKUP_DIR="/root/zero-trust-backup-$(date +%Y%m%d-%H%M%S)"

# Phase tracking
declare -A PHASES_COMPLETED

# ============================================================================
# Pre-flight Checks
# ============================================================================

# Perform pre-flight checks
preflight_checks() {
    print_header "Zero Trust Setup - Pre-flight Checks"

    local ready=true

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        ready=false
    fi

    # Check Ubuntu version
    local os_version=$(lsb_release -rs 2>/dev/null)
    if [[ ! "$os_version" =~ ^(20|22|24)\. ]]; then
        print_warning "Untested Ubuntu version: $os_version"
    fi

    # Check available disk space (need at least 5GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 5242880 ]; then
        print_error "Insufficient disk space (need at least 5GB)"
        ready=false
    fi

    # Check internet connectivity
    if ! ping -c 1 google.com &>/dev/null; then
        print_error "No internet connectivity"
        ready=false
    fi

    # Check if modules exist
    local required_modules=(
        "base/system-update.sh"
        "security/firewall.sh"
        "security/ssh-security.sh"
        "security/system-hardening.sh"
    )

    for module in "${required_modules[@]}"; do
        if [ ! -f "${SRC_DIR}/${module}" ]; then
            print_error "Required module missing: $module"
            ready=false
        fi
    done

    if [ "$ready" = true ]; then
        print_success "All pre-flight checks passed"
        return 0
    else
        print_error "Pre-flight checks failed"
        return 1
    fi
}

# ============================================================================
# Phase 1: System Preparation
# ============================================================================

phase1_system_preparation() {
    print_header "PHASE 1: System Preparation"

    # Create backup directory
    print_status "Creating backup directory..."
    sudo mkdir -p "$ZERO_TRUST_BACKUP_DIR"

    # Load system update module
    source "${SRC_DIR}/base/system-update.sh"

    # Update system
    print_status "Updating system packages..."
    system_update

    # Install essential packages
    print_status "Installing essential packages..."
    install_essential_packages

    # Configure automatic updates
    print_status "Configuring automatic security updates..."
    configure_auto_updates

    PHASES_COMPLETED["system_preparation"]=1
    print_success "Phase 1 completed: System prepared"
    return 0
}

# ============================================================================
# Phase 2: Network Security
# ============================================================================

phase2_network_security() {
    print_header "PHASE 2: Network Security"

    # Load firewall module
    source "${SRC_DIR}/security/firewall.sh"

    # Configure UFW
    print_status "Configuring UFW firewall..."
    configure_ufw

    # Configure Docker firewall if Docker is installed
    if command -v docker &>/dev/null; then
        print_status "Configuring Docker firewall integration..."
        configure_ufw_docker
    fi

    # Load and configure Tailscale if available
    if [ -f "${SRC_DIR}/security/tailscale.sh" ]; then
        source "${SRC_DIR}/security/tailscale.sh"

        if confirm_action "Setup Tailscale VPN for secure access?"; then
            install_tailscale

            if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                configure_tailscale_interactive
            else
                configure_tailscale
            fi

            # Configure firewall for Tailscale
            configure_tailscale_firewall
        fi
    fi

    PHASES_COMPLETED["network_security"]=1
    print_success "Phase 2 completed: Network security configured"
    return 0
}

# ============================================================================
# Phase 3: SSH Hardening
# ============================================================================

phase3_ssh_hardening() {
    print_header "PHASE 3: SSH Hardening"

    # Load SSH security module
    source "${SRC_DIR}/security/ssh-security.sh"

    # Harden SSH configuration
    print_status "Hardening SSH configuration..."
    harden_ssh_config

    # Configure fail2ban for SSH
    print_status "Configuring fail2ban for SSH protection..."
    configure_fail2ban_ssh

    # Generate SSH keys for root
    print_status "Generating SSH keys..."
    generate_ssh_keys "root"

    # Audit SSH configuration
    print_status "Auditing SSH configuration..."
    audit_ssh_config

    PHASES_COMPLETED["ssh_hardening"]=1
    print_success "Phase 3 completed: SSH hardened"
    return 0
}

# ============================================================================
# Phase 4: System Hardening
# ============================================================================

phase4_system_hardening() {
    print_header "PHASE 4: System Hardening"

    # Load system hardening module
    source "${SRC_DIR}/security/system-hardening.sh"

    # Harden kernel parameters
    print_status "Hardening kernel parameters..."
    harden_kernel_parameters

    # Harden file permissions
    print_status "Hardening file permissions..."
    harden_file_permissions

    # Disable unnecessary services
    print_status "Disabling unnecessary services..."
    disable_unnecessary_services

    # Configure process limits
    print_status "Configuring process limits..."
    configure_process_limits

    # Configure PAM
    print_status "Hardening PAM configuration..."
    harden_pam_configuration

    # Configure AppArmor
    print_status "Configuring AppArmor..."
    configure_apparmor

    # Configure auditd
    print_status "Configuring audit daemon..."
    configure_auditd

    PHASES_COMPLETED["system_hardening"]=1
    print_success "Phase 4 completed: System hardened"
    return 0
}

# ============================================================================
# Phase 5: Intrusion Prevention
# ============================================================================

phase5_intrusion_prevention() {
    print_header "PHASE 5: Intrusion Prevention"

    # Load CrowdSec module if available
    if [ -f "${SRC_DIR}/security/crowdsec.sh" ]; then
        source "${SRC_DIR}/security/crowdsec.sh"

        print_status "Installing CrowdSec IPS..."
        install_crowdsec

        print_status "Configuring CrowdSec..."
        configure_crowdsec

        print_status "Installing CrowdSec collections..."
        install_collections
        install_scenarios

        print_status "Installing firewall bouncer..."
        install_firewall_bouncer

        PHASES_COMPLETED["intrusion_prevention"]=1
        print_success "Phase 5 completed: Intrusion prevention configured"
    else
        print_warning "CrowdSec module not found, skipping IPS setup"
    fi

    return 0
}

# ============================================================================
# Phase 6: Monitoring Setup
# ============================================================================

phase6_monitoring_setup() {
    print_header "PHASE 6: Monitoring Setup"

    # Load monitoring tools module if available
    if [ -f "${SRC_DIR}/monitoring/tools.sh" ]; then
        source "${SRC_DIR}/monitoring/tools.sh"

        print_status "Installing monitoring tools..."

        # Install Lynis
        install_lynis

        # Install AIDE
        install_aide

        # Install Logwatch
        install_logwatch

        # Install metrics tools
        install_metrics_tools

        # Configure alerts if email is provided
        if [ -n "${ADMIN_EMAIL:-}" ]; then
            configure_alerts "$ADMIN_EMAIL"
        fi

        PHASES_COMPLETED["monitoring_setup"]=1
        print_success "Phase 6 completed: Monitoring configured"
    else
        print_warning "Monitoring module not found, skipping monitoring setup"
    fi

    return 0
}

# ============================================================================
# Phase 7: Container Security
# ============================================================================

phase7_container_security() {
    print_header "PHASE 7: Container Security"

    # Check if Docker is installed
    if command -v docker &>/dev/null; then
        # Load Docker module if available
        if [ -f "${SRC_DIR}/containers/docker.sh" ]; then
            source "${SRC_DIR}/containers/docker.sh"

            print_status "Configuring Docker security..."
            configure_docker_security

            print_status "Auditing Docker security..."
            audit_docker_security

            PHASES_COMPLETED["container_security"]=1
            print_success "Phase 7 completed: Container security configured"
        else
            print_warning "Docker module not found, skipping Docker security"
        fi
    else
        print_status "Docker not installed, skipping container security"
    fi

    return 0
}

# ============================================================================
# Phase 8: Cloudflare Integration
# ============================================================================

phase8_cloudflare_integration() {
    print_header "PHASE 8: Cloudflare Integration (Optional)"

    if [ -f "${SRC_DIR}/security/cloudflare.sh" ]; then
        if confirm_action "Setup Cloudflare Tunnel for secure access?"; then
            source "${SRC_DIR}/security/cloudflare.sh"

            # Interactive setup
            setup_cloudflare_interactive

            PHASES_COMPLETED["cloudflare_integration"]=1
            print_success "Phase 8 completed: Cloudflare configured"
        else
            print_status "Skipping Cloudflare integration"
        fi
    else
        print_status "Cloudflare module not found, skipping"
    fi

    return 0
}

# ============================================================================
# Phase 9: Validation
# ============================================================================

phase9_validation() {
    print_header "PHASE 9: Security Validation"

    local validation_passed=true

    # Check firewall status
    print_status "Checking firewall status..."
    if sudo ufw status | grep -q "Status: active"; then
        print_success "Firewall is active"
    else
        print_error "Firewall is not active"
        validation_passed=false
    fi

    # Check SSH configuration
    print_status "Checking SSH configuration..."
    if sudo sshd -t -f /etc/ssh/sshd_config 2>/dev/null; then
        print_success "SSH configuration is valid"
    else
        print_error "SSH configuration has errors"
        validation_passed=false
    fi

    # Check fail2ban status
    print_status "Checking fail2ban status..."
    if systemctl is-active fail2ban &>/dev/null; then
        print_success "Fail2ban is active"
    else
        print_warning "Fail2ban is not active"
    fi

    # Check AppArmor status
    print_status "Checking AppArmor status..."
    if systemctl is-active apparmor &>/dev/null; then
        print_success "AppArmor is active"
    else
        print_warning "AppArmor is not active"
    fi

    # Check CrowdSec status if installed
    if command -v cscli &>/dev/null; then
        print_status "Checking CrowdSec status..."
        if systemctl is-active crowdsec &>/dev/null; then
            print_success "CrowdSec is active"
        else
            print_error "CrowdSec is not active"
            validation_passed=false
        fi
    fi

    # Run CIS compliance check if available
    if declare -f check_cis_compliance &>/dev/null; then
        print_status "Running CIS compliance check..."
        check_cis_compliance
    fi

    # Run Lynis audit if available
    if command -v lynis &>/dev/null; then
        print_status "Running quick security audit..."
        timeout 60 sudo lynis audit system --quick --quiet
    fi

    if [ "$validation_passed" = true ]; then
        PHASES_COMPLETED["validation"]=1
        print_success "Phase 9 completed: Validation passed"
    else
        print_warning "Phase 9: Some validation checks failed"
    fi

    return 0
}

# ============================================================================
# Phase 10: Final Report
# ============================================================================

phase10_final_report() {
    print_header "PHASE 10: Final Report"

    # Generate report
    local report_file="$ZERO_TRUST_BACKUP_DIR/zero-trust-report.txt"

    {
        echo "Zero Trust Security Setup Report"
        echo "================================"
        echo "Date: $(date)"
        echo "Hostname: $(hostname -f)"
        echo "OS Version: $(lsb_release -ds)"
        echo ""
        echo "Completed Phases:"

        for phase in "${!PHASES_COMPLETED[@]}"; do
            echo "  ✓ $phase"
        done

        echo ""
        echo "Security Components Status:"
        echo "  Firewall: $(sudo ufw status | grep Status | awk '{print $2}')"
        echo "  SSH: $(systemctl is-active sshd)"
        echo "  Fail2ban: $(systemctl is-active fail2ban 2>/dev/null || echo 'not installed')"
        echo "  AppArmor: $(systemctl is-active apparmor)"
        echo "  Auditd: $(systemctl is-active auditd 2>/dev/null || echo 'not installed')"

        if command -v cscli &>/dev/null; then
            echo "  CrowdSec: $(systemctl is-active crowdsec)"
        fi

        if command -v tailscale &>/dev/null; then
            echo "  Tailscale: $(tailscale status &>/dev/null && echo 'connected' || echo 'not connected')"
        fi

        echo ""
        echo "Network Configuration:"
        echo "  Open Ports:"
        sudo ufw status numbered | grep ALLOW | head -10

        echo ""
        echo "Backup Location: $ZERO_TRUST_BACKUP_DIR"

    } | tee "$report_file"

    print_success "Report saved to: $report_file"

    # Show important reminders
    print_header "Important Reminders"
    echo "1. Change default passwords for all services"
    echo "2. Configure backup strategy for critical data"
    echo "3. Set up log rotation and retention policies"
    echo "4. Review and customize firewall rules as needed"
    echo "5. Test disaster recovery procedures"
    echo "6. Schedule regular security audits"
    echo "7. Keep system and security tools updated"

    if [ -n "${ADMIN_EMAIL:-}" ]; then
        echo "8. Verify alert emails are being received at: $ADMIN_EMAIL"
    fi

    PHASES_COMPLETED["final_report"]=1
    print_success "Zero Trust setup completed successfully!"

    return 0
}

# ============================================================================
# Main Orchestration
# ============================================================================

# Run complete Zero Trust setup
run_zero_trust_setup() {
    print_header "Zero Trust Security Architecture Setup"

    # Start logging
    exec 2>&1 | tee -a "$ZERO_TRUST_LOG"

    echo "Starting Zero Trust setup at $(date)"
    echo "This process will configure comprehensive security measures"
    echo ""

    # Confirm before proceeding
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        if ! confirm_action "This will make significant security changes. Continue?"; then
            print_warning "Setup cancelled by user"
            return 1
        fi
    fi

    # Run pre-flight checks
    if ! preflight_checks; then
        print_error "Pre-flight checks failed. Please resolve issues and try again."
        return 1
    fi

    # Execute phases in order
    local phases=(
        "phase1_system_preparation"
        "phase2_network_security"
        "phase3_ssh_hardening"
        "phase4_system_hardening"
        "phase5_intrusion_prevention"
        "phase6_monitoring_setup"
        "phase7_container_security"
        "phase8_cloudflare_integration"
        "phase9_validation"
        "phase10_final_report"
    )

    for phase_func in "${phases[@]}"; do
        if ! $phase_func; then
            print_error "Phase failed: $phase_func"
            if [[ "$INTERACTIVE_MODE" == "true" ]]; then
                if ! confirm_action "Continue with remaining phases?"; then
                    print_error "Setup aborted at $phase_func"
                    return 1
                fi
            fi
        fi
        echo ""
    done

    return 0
}

# Run specific phase
run_specific_phase() {
    local phase="${1:-}"

    case "$phase" in
        1|preparation)
            phase1_system_preparation
            ;;
        2|network)
            phase2_network_security
            ;;
        3|ssh)
            phase3_ssh_hardening
            ;;
        4|hardening)
            phase4_system_hardening
            ;;
        5|ips)
            phase5_intrusion_prevention
            ;;
        6|monitoring)
            phase6_monitoring_setup
            ;;
        7|container)
            phase7_container_security
            ;;
        8|cloudflare)
            phase8_cloudflare_integration
            ;;
        9|validation)
            phase9_validation
            ;;
        10|report)
            phase10_final_report
            ;;
        *)
            print_error "Invalid phase: $phase"
            echo "Valid phases: 1-10 or preparation|network|ssh|hardening|ips|monitoring|container|cloudflare|validation|report"
            return 1
            ;;
    esac
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Zero Trust Orchestrator v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --run                   Run complete Zero Trust setup
    --phase PHASE           Run specific phase only
    --preflight             Run pre-flight checks only
    --validate              Run validation only
    --report                Generate status report
    --help                  Show this help message

PHASES:
    1  | preparation     - System updates and preparation
    2  | network        - Network security and firewall
    3  | ssh            - SSH hardening
    4  | hardening      - System hardening
    5  | ips            - Intrusion prevention
    6  | monitoring     - Monitoring tools
    7  | container      - Container security
    8  | cloudflare     - Cloudflare integration
    9  | validation     - Security validation
    10 | report         - Final report

EXAMPLES:
    # Run complete setup
    $0 --run

    # Run specific phase
    $0 --phase ssh

    # Validate setup
    $0 --validate

ENVIRONMENT VARIABLES:
    ADMIN_EMAIL         Email for alerts and notifications
    INTERACTIVE_MODE    Set to 'false' for non-interactive
    TAILSCALE_AUTH_KEY  Tailscale authentication key
    CLOUDFLARE_TOKEN    Cloudflare API token

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
export -f preflight_checks
export -f phase1_system_preparation phase2_network_security
export -f phase3_ssh_hardening phase4_system_hardening
export -f phase5_intrusion_prevention phase6_monitoring_setup
export -f phase7_container_security phase8_cloudflare_integration
export -f phase9_validation phase10_final_report
export -f run_zero_trust_setup run_specific_phase

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")"
source "${SRC_DIR}/lib/common.sh" 2>/dev/null || true
source "${SRC_DIR}/lib/config.sh" 2>/dev/null || true
source "${SRC_DIR}/lib/backup.sh" 2>/dev/null || true

# Set defaults
INTERACTIVE_MODE="${INTERACTIVE_MODE:-true}"

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --run)
            run_zero_trust_setup
            ;;
        --phase)
            run_specific_phase "${2:-}"
            ;;
        --preflight)
            preflight_checks
            ;;
        --validate)
            phase9_validation
            ;;
        --report)
            phase10_final_report
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Zero Trust Orchestrator v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            echo ""
            echo "Quick start: $0 --run"
            ;;
    esac
fi