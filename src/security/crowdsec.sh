#!/bin/bash
# CrowdSec module - Intrusion Prevention System
# Manages CrowdSec installation, configuration, and bouncer setup

# Script metadata
readonly MODULE_VERSION="1.0.0"
readonly MODULE_NAME="crowdsec"

# CrowdSec configuration
readonly CROWDSEC_CONFIG_DIR="/etc/crowdsec"
readonly CROWDSEC_DATA_DIR="/var/lib/crowdsec"
readonly CROWDSEC_HUB_UPDATE="${CROWDSEC_HUB_UPDATE:-true}"

# ============================================================================
# CrowdSec Installation
# ============================================================================

# Install CrowdSec
install_crowdsec() {
    print_status "Installing CrowdSec IPS..."

    # Check if already installed
    if command -v cscli &>/dev/null; then
        print_warning "CrowdSec is already installed"
        local version=$(cscli version 2>/dev/null | grep version | head -1)
        print_status "Current version: $version"

        if ! confirm_action "Reinstall CrowdSec?"; then
            return 0
        fi
    fi

    # Install dependencies
    print_status "Installing dependencies..."
    sudo apt update
    sudo apt install -y curl gnupg

    # Add CrowdSec repository
    print_status "Adding CrowdSec repository..."
    curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash

    # Install CrowdSec
    print_status "Installing CrowdSec packages..."
    sudo apt update
    sudo apt install -y crowdsec

    # Enable and start CrowdSec
    sudo systemctl enable crowdsec
    sudo systemctl start crowdsec

    # Verify installation
    if cscli version &>/dev/null; then
        print_success "CrowdSec installed successfully"
        cscli version
    else
        print_error "CrowdSec installation failed"
        return 1
    fi

    # Update hub if requested
    if [[ "$CROWDSEC_HUB_UPDATE" == "true" ]]; then
        update_crowdsec_hub
    fi

    return 0
}

# ============================================================================
# CrowdSec Configuration
# ============================================================================

# Configure CrowdSec
configure_crowdsec() {
    print_status "Configuring CrowdSec..."

    # Backup configuration
    backup_file "$CROWDSEC_CONFIG_DIR/config.yaml"

    # Configure acquisition
    configure_acquisition

    # Configure profiles
    configure_profiles

    # Configure notifications
    configure_notifications

    # Reload CrowdSec
    sudo systemctl reload crowdsec

    print_success "CrowdSec configured"
    return 0
}

# Configure acquisition (what to monitor)
configure_acquisition() {
    print_status "Configuring CrowdSec acquisition..."

    cat << 'EOF' | sudo tee "$CROWDSEC_CONFIG_DIR/acquis.yaml" > /dev/null
# CrowdSec Acquisition Configuration
# Defines what logs to monitor

# SSH logs
filenames:
  - /var/log/auth.log
  - /var/log/secure
labels:
  type: syslog

---
# Nginx logs (if present)
filenames:
  - /var/log/nginx/access.log
  - /var/log/nginx/error.log
labels:
  type: nginx

---
# Apache logs (if present)
filenames:
  - /var/log/apache2/access.log
  - /var/log/apache2/error.log
labels:
  type: apache2

---
# Docker logs
filenames:
  - /var/lib/docker/containers/*/*-json.log
labels:
  type: docker

---
# Kernel logs
filenames:
  - /var/log/kern.log
labels:
  type: syslog

---
# UFW logs
filenames:
  - /var/log/ufw.log
labels:
  type: ufw
EOF

    print_success "Acquisition configured"
}

# Configure profiles (what actions to take)
configure_profiles() {
    print_status "Configuring CrowdSec profiles..."

    cat << 'EOF' | sudo tee "$CROWDSEC_CONFIG_DIR/profiles.yaml" > /dev/null
name: default_ip_remediation
filters:
  - Alert.Remediation == true && Alert.GetScope() == "Ip"
decisions:
  - type: ban
    duration: 4h
on_success: break

---
name: aggressive_ip_remediation
filters:
  - Alert.Remediation == true && Alert.GetScope() == "Ip" && Alert.Confidence >= 80
decisions:
  - type: ban
    duration: 24h
on_success: break

---
name: captcha_remediation
filters:
  - Alert.Remediation == true && Alert.GetScope() == "Ip" && Alert.Confidence < 80
decisions:
  - type: captcha
    duration: 4h
on_success: break
EOF

    print_success "Profiles configured"
}

# Configure notifications
configure_notifications() {
    local email="${1:-$ADMIN_EMAIL}"

    if [ -z "$email" ]; then
        print_warning "No email configured for notifications"
        return 0
    fi

    print_status "Configuring CrowdSec notifications..."

    cat << EOF | sudo tee "$CROWDSEC_CONFIG_DIR/notifications/email.yaml" > /dev/null
type: email
name: email_notification

smtp_host: localhost
smtp_port: 25
smtp_username: ""
smtp_password: ""
sender_email: crowdsec@$(hostname -f)
receiver_emails:
  - $email

format: |
  CrowdSec Alert

  Scenario: {{.Scenario}}
  IP: {{.Source.IP}}
  Country: {{.Source.Country}}
  AS: {{.Source.AS}}
  Confidence: {{.Confidence}}
  Duration: {{.Duration}}
EOF

    print_success "Notifications configured"
}

# ============================================================================
# Hub Management
# ============================================================================

# Update CrowdSec hub
update_crowdsec_hub() {
    print_status "Updating CrowdSec hub..."

    sudo cscli hub update

    print_success "CrowdSec hub updated"
    return 0
}

# Install collections
install_collections() {
    print_status "Installing CrowdSec collections..."

    local collections=(
        "crowdsecurity/linux"
        "crowdsecurity/sshd"
        "crowdsecurity/nginx"
        "crowdsecurity/apache2"
        "crowdsecurity/iptables"
    )

    for collection in "${collections[@]}"; do
        print_status "Installing collection: $collection"
        sudo cscli collections install "$collection" 2>/dev/null || true
    done

    # Reload CrowdSec
    sudo systemctl reload crowdsec

    print_success "Collections installed"
    return 0
}

# Install scenarios
install_scenarios() {
    print_status "Installing CrowdSec scenarios..."

    local scenarios=(
        "crowdsecurity/ssh-bf"
        "crowdsecurity/ssh-slow-bf"
        "crowdsecurity/http-probing"
        "crowdsecurity/http-crawl-non-static"
        "crowdsecurity/http-sensitive-files"
    )

    for scenario in "${scenarios[@]}"; do
        print_status "Installing scenario: $scenario"
        sudo cscli scenarios install "$scenario" 2>/dev/null || true
    done

    # Reload CrowdSec
    sudo systemctl reload crowdsec

    print_success "Scenarios installed"
    return 0
}

# ============================================================================
# Bouncer Management
# ============================================================================

# Install firewall bouncer
install_firewall_bouncer() {
    print_status "Installing CrowdSec firewall bouncer..."

    # Install bouncer package
    sudo apt update
    sudo apt install -y crowdsec-firewall-bouncer-iptables

    # Generate API key for bouncer
    local api_key=$(sudo cscli bouncers add firewall-bouncer -o raw 2>/dev/null || \
                    sudo cscli bouncers delete firewall-bouncer 2>/dev/null && \
                    sudo cscli bouncers add firewall-bouncer -o raw)

    # Configure bouncer
    cat << EOF | sudo tee /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml > /dev/null
api_url: http://localhost:8080
api_key: $api_key
mode: iptables
update_frequency: 10s
log_mode: file
log_dir: /var/log/crowdsec-firewall-bouncer/
log_level: info
EOF

    # Enable and start bouncer
    sudo systemctl enable crowdsec-firewall-bouncer
    sudo systemctl restart crowdsec-firewall-bouncer

    print_success "Firewall bouncer installed"
    return 0
}

# Install Nginx bouncer
install_nginx_bouncer() {
    print_status "Installing CrowdSec Nginx bouncer..."

    # Check if Nginx is installed
    if ! command -v nginx &>/dev/null; then
        print_warning "Nginx not installed, skipping bouncer installation"
        return 0
    fi

    # Install Lua dependencies
    sudo apt update
    sudo apt install -y libnginx-mod-http-lua lua5.1 liblua5.1-dev

    # Download and install bouncer
    local bouncer_version="v1.0.5"
    wget -O /tmp/crowdsec-nginx-bouncer.tgz \
        "https://github.com/crowdsecurity/cs-nginx-bouncer/releases/download/${bouncer_version}/crowdsec-nginx-bouncer.tgz"

    cd /tmp && tar xzf crowdsec-nginx-bouncer.tgz
    cd crowdsec-nginx-bouncer-* && sudo ./install.sh

    # Generate API key
    local api_key=$(sudo cscli bouncers add nginx-bouncer -o raw 2>/dev/null || \
                    sudo cscli bouncers delete nginx-bouncer 2>/dev/null && \
                    sudo cscli bouncers add nginx-bouncer -o raw)

    # Configure bouncer
    cat << EOF | sudo tee /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf > /dev/null
API_URL=http://localhost:8080
API_KEY=$api_key
CACHE_EXPIRATION=1
REQUEST_TIMEOUT=0.2
UPDATE_FREQUENCY=10
EOF

    # Reload Nginx
    sudo nginx -t && sudo systemctl reload nginx

    print_success "Nginx bouncer installed"
    return 0
}

# Install custom bouncer
install_custom_bouncer() {
    local bouncer_name="${1:-custom-bouncer}"

    print_status "Installing custom bouncer: $bouncer_name"

    # Generate API key
    local api_key=$(sudo cscli bouncers add "$bouncer_name" -o raw)

    echo "Bouncer: $bouncer_name"
    echo "API Key: $api_key"
    echo "API URL: http://localhost:8080"

    print_success "Custom bouncer $bouncer_name created"
    return 0
}

# ============================================================================
# Monitoring and Management
# ============================================================================

# Show CrowdSec status
show_crowdsec_status() {
    print_header "CrowdSec Status"

    # Service status
    echo "Service Status:"
    systemctl status crowdsec --no-pager | head -15

    echo ""

    # Metrics
    echo "Metrics:"
    sudo cscli metrics

    echo ""

    # Decisions
    echo "Active Decisions:"
    sudo cscli decisions list

    echo ""

    # Alerts
    echo "Recent Alerts:"
    sudo cscli alerts list --limit 10

    echo ""

    # Bouncers
    echo "Registered Bouncers:"
    sudo cscli bouncers list

    echo ""

    # Collections
    echo "Installed Collections:"
    sudo cscli collections list

    return 0
}

# Show CrowdSec dashboard
show_dashboard() {
    print_status "CrowdSec Dashboard"

    # Show metrics
    sudo cscli metrics

    # Monitor in real-time if requested
    if confirm_action "Monitor in real-time?"; then
        watch -n 2 'sudo cscli metrics'
    fi

    return 0
}

# Inspect specific alert
inspect_alert() {
    local alert_id="${1:-}"

    if [ -z "$alert_id" ]; then
        print_error "Alert ID required"
        return 1
    fi

    print_status "Inspecting alert: $alert_id"

    sudo cscli alerts inspect "$alert_id"

    return 0
}

# ============================================================================
# Decision Management
# ============================================================================

# Add manual decision (ban)
add_decision() {
    local ip="${1:-}"
    local duration="${2:-4h}"
    local reason="${3:-Manual ban}"

    if [ -z "$ip" ]; then
        print_error "IP address required"
        return 1
    fi

    print_status "Adding decision for IP: $ip"

    sudo cscli decisions add --ip "$ip" --duration "$duration" --reason "$reason"

    print_success "Decision added for $ip"
    return 0
}

# Remove decision
remove_decision() {
    local ip="${1:-}"

    if [ -z "$ip" ]; then
        print_error "IP address required"
        return 1
    fi

    print_status "Removing decision for IP: $ip"

    sudo cscli decisions delete --ip "$ip"

    print_success "Decision removed for $ip"
    return 0
}

# ============================================================================
# Testing and Validation
# ============================================================================

# Test CrowdSec installation
test_crowdsec() {
    print_header "Testing CrowdSec Installation"

    local tests_passed=0
    local tests_failed=0

    # Test: CrowdSec service
    if systemctl is-active crowdsec &>/dev/null; then
        print_success "CrowdSec service is running"
        ((tests_passed++))
    else
        print_error "CrowdSec service is not running"
        ((tests_failed++))
    fi

    # Test: API availability
    if curl -s http://localhost:8080/v1/decisions &>/dev/null; then
        print_success "CrowdSec API is accessible"
        ((tests_passed++))
    else
        print_error "CrowdSec API is not accessible"
        ((tests_failed++))
    fi

    # Test: Bouncer connectivity
    local bouncers=$(sudo cscli bouncers list -o json | jq length)
    if [ "$bouncers" -gt 0 ]; then
        print_success "$bouncers bouncer(s) registered"
        ((tests_passed++))
    else
        print_warning "No bouncers registered"
        ((tests_failed++))
    fi

    # Test: Collections installed
    local collections=$(sudo cscli collections list -o json | jq '[.collections[] | select(.status == "enabled")] | length')
    if [ "$collections" -gt 0 ]; then
        print_success "$collections collection(s) enabled"
        ((tests_passed++))
    else
        print_warning "No collections enabled"
        ((tests_failed++))
    fi

    # Summary
    echo ""
    echo "Test Results: $tests_passed passed, $tests_failed failed"

    return $tests_failed
}

# ============================================================================
# Complete Setup
# ============================================================================

# Run complete CrowdSec setup
setup_crowdsec_complete() {
    print_header "Complete CrowdSec Setup"

    # Install CrowdSec
    install_crowdsec

    # Configure CrowdSec
    configure_crowdsec

    # Install collections and scenarios
    install_collections
    install_scenarios

    # Install firewall bouncer
    install_firewall_bouncer

    # Install Nginx bouncer if applicable
    if command -v nginx &>/dev/null; then
        install_nginx_bouncer
    fi

    # Test installation
    test_crowdsec

    print_success "CrowdSec setup completed!"
    print_warning "Remember to:"
    echo "  • Register at https://app.crowdsec.net for console access"
    echo "  • Review and customize scenarios as needed"
    echo "  • Configure additional bouncers if required"

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
CrowdSec Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --install               Install CrowdSec
    --configure             Configure CrowdSec
    --update-hub            Update CrowdSec hub
    --install-collections   Install recommended collections
    --install-scenarios     Install security scenarios
    --install-fw-bouncer    Install firewall bouncer
    --install-nginx-bouncer Install Nginx bouncer
    --status                Show CrowdSec status
    --dashboard             Show dashboard
    --add-decision IP       Ban an IP address
    --remove-decision IP    Unban an IP address
    --test                  Test CrowdSec installation
    --complete              Run complete setup
    --help                  Show this help message

EXAMPLES:
    # Complete setup
    $0 --complete

    # Check status
    $0 --status

    # Ban an IP
    $0 --add-decision 192.168.1.100

    # Test installation
    $0 --test

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
export -f install_crowdsec configure_crowdsec
export -f configure_acquisition configure_profiles configure_notifications
export -f update_crowdsec_hub install_collections install_scenarios
export -f install_firewall_bouncer install_nginx_bouncer install_custom_bouncer
export -f show_crowdsec_status show_dashboard inspect_alert
export -f add_decision remove_decision
export -f test_crowdsec setup_crowdsec_complete

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/backup.sh" 2>/dev/null || true

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --install)
            install_crowdsec
            ;;
        --configure)
            configure_crowdsec
            ;;
        --update-hub)
            update_crowdsec_hub
            ;;
        --install-collections)
            install_collections
            ;;
        --install-scenarios)
            install_scenarios
            ;;
        --install-fw-bouncer)
            install_firewall_bouncer
            ;;
        --install-nginx-bouncer)
            install_nginx_bouncer
            ;;
        --status)
            show_crowdsec_status
            ;;
        --dashboard)
            show_dashboard
            ;;
        --add-decision)
            add_decision "${2}" "${3:-4h}" "${4:-Manual ban}"
            ;;
        --remove-decision)
            remove_decision "${2}"
            ;;
        --test)
            test_crowdsec
            ;;
        --complete)
            setup_crowdsec_complete
            ;;
        --help)
            show_help
            ;;
        *)
            echo "CrowdSec Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi