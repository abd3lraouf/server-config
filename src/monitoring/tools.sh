#!/bin/bash
# Monitoring Tools module - System monitoring and alerting tools
# Manages installation and configuration of monitoring utilities

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="monitoring-tools"

# ============================================================================
# Lynis Security Auditing
# ============================================================================

# Install Lynis
install_lynis() {
    print_status "Installing Lynis security auditing tool..."

    # Check if already installed
    if command -v lynis &>/dev/null; then
        print_warning "Lynis is already installed"
        lynis show version
        return 0
    fi

    # Add Lynis repository
    print_status "Adding Lynis repository..."
    wget -O - https://packages.cisofy.com/keys/cisofy-software-public.key | sudo apt-key add -
    echo "deb https://packages.cisofy.com/community/lynis/deb/ stable main" | sudo tee /etc/apt/sources.list.d/cisofy-lynis.list

    # Install Lynis
    sudo apt update
    sudo apt install -y lynis

    # Verify installation
    if command -v lynis &>/dev/null; then
        print_success "Lynis installed successfully"
        lynis show version
    else
        print_error "Lynis installation failed"
        return 1
    fi

    return 0
}

# Run Lynis audit
run_lynis_audit() {
    print_status "Running Lynis security audit..."

    if ! command -v lynis &>/dev/null; then
        print_error "Lynis is not installed"
        return 1
    fi

    # Create report directory
    local report_dir="/var/log/lynis"
    sudo mkdir -p "$report_dir"

    # Run audit with timeout to prevent hanging
    print_status "This may take a few minutes..."
    timeout 300 sudo lynis audit system --quick 2>&1 | tee "$report_dir/audit-$(date +%Y%m%d-%H%M%S).log"

    # Show summary
    echo ""
    print_status "Audit Summary:"
    sudo lynis show warnings
    sudo lynis show suggestions | head -20

    print_success "Lynis audit completed"
    echo "Full report saved to: $report_dir"

    return 0
}

# ============================================================================
# AIDE File Integrity Monitoring
# ============================================================================

# Install AIDE
install_aide() {
    print_status "Installing AIDE file integrity monitoring..."

    # Check if already installed
    if command -v aide &>/dev/null; then
        print_warning "AIDE is already installed"
        return 0
    fi

    # Install AIDE
    sudo DEBIAN_FRONTEND=noninteractive apt install -y aide aide-common

    # Configure AIDE
    configure_aide

    print_success "AIDE installed successfully"
    return 0
}

# Configure AIDE
configure_aide() {
    print_status "Configuring AIDE..."

    # Backup existing configuration
    backup_file "/etc/aide/aide.conf"

    # Add custom rules
    cat << 'EOF' | sudo tee -a /etc/aide/aide.conf.d/99_custom > /dev/null
# Custom AIDE Rules

# Critical system binaries
/bin R+b+sha256
/sbin R+b+sha256
/usr/bin R+b+sha256
/usr/sbin R+b+sha256

# Configuration files
/etc R+b+sha256

# Exclude frequently changing files
!/var/log
!/var/cache
!/var/tmp
!/tmp
!/proc
!/sys
!/dev
EOF

    # Update AIDE configuration
    sudo update-aide.conf

    print_success "AIDE configured"
    return 0
}

# Initialize AIDE database
initialize_aide() {
    print_status "Initializing AIDE database (this may take several minutes)..."

    # Initialize database in background
    sudo aideinit -y -f

    # Move database to proper location
    sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

    print_success "AIDE database initialized"
    return 0
}

# Run AIDE check
run_aide_check() {
    print_status "Running AIDE integrity check..."

    if [ ! -f /var/lib/aide/aide.db ]; then
        print_error "AIDE database not initialized"
        print_status "Run --initialize-aide first"
        return 1
    fi

    # Run check
    sudo aide --check

    print_success "AIDE check completed"
    return 0
}

# ============================================================================
# Logwatch Log Analysis
# ============================================================================

# Install Logwatch
install_logwatch() {
    print_status "Installing Logwatch log analyzer..."

    # Check if already installed
    if command -v logwatch &>/dev/null; then
        print_warning "Logwatch is already installed"
        return 0
    fi

    # Install Logwatch
    sudo apt update
    sudo apt install -y logwatch

    # Configure Logwatch
    configure_logwatch

    print_success "Logwatch installed successfully"
    return 0
}

# Configure Logwatch
configure_logwatch() {
    print_status "Configuring Logwatch..."

    local email="${1:-$ADMIN_EMAIL}"

    # Create custom configuration
    cat << EOF | sudo tee /etc/logwatch/conf/logwatch.conf > /dev/null
# Logwatch Configuration
MailTo = ${email:-root}
MailFrom = Logwatch <logwatch@$(hostname -f)>
Range = yesterday
Detail = Med
Service = All
Format = html
EOF

    print_success "Logwatch configured"
    return 0
}

# Run Logwatch report
run_logwatch_report() {
    print_status "Generating Logwatch report..."

    if ! command -v logwatch &>/dev/null; then
        print_error "Logwatch is not installed"
        return 1
    fi

    # Generate report
    sudo logwatch --output stdout --format text --range today

    print_success "Logwatch report generated"
    return 0
}

# ============================================================================
# Netdata Real-time Monitoring
# ============================================================================

# Install Netdata
install_netdata() {
    print_status "Installing Netdata real-time monitoring..."

    # Check if already installed
    if systemctl is-active netdata &>/dev/null; then
        print_warning "Netdata is already installed and running"
        return 0
    fi

    # Install using official script
    print_status "Downloading and installing Netdata..."
    bash <(curl -Ss https://my-netdata.io/kickstart.sh) --dont-wait --disable-telemetry

    # Configure Netdata
    configure_netdata

    # Enable and start service
    sudo systemctl enable netdata
    sudo systemctl restart netdata

    print_success "Netdata installed successfully"
    print_status "Access Netdata at: http://$(hostname -I | awk '{print $1}'):19999"

    return 0
}

# Configure Netdata
configure_netdata() {
    print_status "Configuring Netdata..."

    # Backup configuration
    backup_file "/etc/netdata/netdata.conf"

    # Basic security configuration
    cat << 'EOF' | sudo tee -a /etc/netdata/netdata.conf > /dev/null

[web]
    # Bind to localhost only (use reverse proxy for external access)
    bind to = 127.0.0.1

    # Disable registry
    enabled = no

[global]
    # Reduce memory usage
    page cache size = 32
    dbengine multihost disk space = 256

    # Disable external plugins
    enable running new plugins = no
EOF

    print_success "Netdata configured"
    return 0
}

# ============================================================================
# Glances System Monitor
# ============================================================================

# Install Glances
install_glances() {
    print_status "Installing Glances system monitor..."

    # Check if already installed
    if command -v glances &>/dev/null; then
        print_warning "Glances is already installed"
        glances --version
        return 0
    fi

    # Install Glances
    sudo apt update
    sudo apt install -y glances

    # Install web UI dependencies
    if confirm_action "Install Glances web UI?"; then
        sudo apt install -y python3-bottle
    fi

    print_success "Glances installed successfully"
    return 0
}

# Start Glances web server
start_glances_web() {
    print_status "Starting Glances web server..."

    if ! command -v glances &>/dev/null; then
        print_error "Glances is not installed"
        return 1
    fi

    # Start in background
    nohup glances -w --bind 127.0.0.1 --port 61208 &>/dev/null &

    print_success "Glances web server started"
    print_status "Access at: http://localhost:61208"

    return 0
}

# ============================================================================
# System Metrics Collection
# ============================================================================

# Install metrics collection tools
install_metrics_tools() {
    print_status "Installing system metrics tools..."

    local tools=(
        "sysstat"      # System activity reporter
        "iotop"        # I/O monitor
        "iftop"        # Network monitor
        "nethogs"      # Network usage by process
        "dstat"        # Versatile resource statistics
        "vnstat"       # Network traffic monitor
        "ncdu"         # Disk usage analyzer
        "btop"         # Enhanced system monitor
    )

    sudo apt update

    for tool in "${tools[@]}"; do
        if ! command -v "${tool%% *}" &>/dev/null; then
            print_status "Installing $tool..."
            sudo apt install -y "$tool"
        else
            print_debug "$tool already installed"
        fi
    done

    print_success "Metrics tools installed"
    return 0
}

# ============================================================================
# Monitoring Dashboard
# ============================================================================

# Show monitoring dashboard
show_monitoring_dashboard() {
    print_header "System Monitoring Dashboard"

    # System info
    echo "System Information:"
    echo "  Hostname: $(hostname -f)"
    echo "  Uptime: $(uptime -p)"
    echo "  Load: $(uptime | awk -F'load average:' '{print $2}')"
    echo ""

    # Memory usage
    echo "Memory Usage:"
    free -h
    echo ""

    # Disk usage
    echo "Disk Usage:"
    df -h | grep -E '^/dev/'
    echo ""

    # Top processes
    echo "Top Processes (by CPU):"
    ps aux | sort -nrk 3,3 | head -5
    echo ""

    # Network connections
    echo "Network Connections:"
    ss -tunap | head -10
    echo ""

    # Recent security events
    if [ -f /var/log/auth.log ]; then
        echo "Recent Authentication Events:"
        sudo tail -5 /var/log/auth.log
    fi

    return 0
}

# ============================================================================
# Alerting Configuration
# ============================================================================

# Configure system alerts
configure_alerts() {
    local email="${1:-$ADMIN_EMAIL}"

    print_status "Configuring system alerts..."

    if [ -z "$email" ]; then
        print_error "Email address required for alerts"
        return 1
    fi

    # Configure root mail alias
    echo "root: $email" | sudo tee -a /etc/aliases
    sudo newaliases

    # Create disk space alert script
    cat << 'EOF' | sudo tee /usr/local/bin/disk-space-alert.sh > /dev/null
#!/bin/bash
THRESHOLD=80
HOSTNAME=$(hostname -f)

df -H | grep -vE '^Filesystem|tmpfs|cdrom|udev' | awk '{ print $5 " " $1 }' | while read output; do
    usage=$(echo $output | awk '{ print $1}' | cut -d'%' -f1)
    partition=$(echo $output | awk '{ print $2 }')

    if [ $usage -ge $THRESHOLD ]; then
        echo "Warning: Disk usage on $partition is ${usage}% on $HOSTNAME" | mail -s "Disk Space Alert: $HOSTNAME" root
    fi
done
EOF

    sudo chmod +x /usr/local/bin/disk-space-alert.sh

    # Add to crontab
    (crontab -l 2>/dev/null; echo "0 */6 * * * /usr/local/bin/disk-space-alert.sh") | crontab -

    print_success "Alerts configured for $email"
    return 0
}

# ============================================================================
# Complete Setup
# ============================================================================

# Install all monitoring tools
setup_monitoring_complete() {
    print_header "Complete Monitoring Setup"

    # Install tools
    install_lynis
    install_aide
    install_logwatch
    install_glances
    install_metrics_tools

    # Optional: Install Netdata
    if confirm_action "Install Netdata real-time monitoring?"; then
        install_netdata
    fi

    # Initialize AIDE
    if confirm_action "Initialize AIDE database (takes time)?"; then
        initialize_aide
    fi

    # Configure alerts
    if [ -n "$ADMIN_EMAIL" ]; then
        configure_alerts "$ADMIN_EMAIL"
    fi

    print_success "Monitoring tools setup completed!"
    print_warning "Remember to:"
    echo "  • Schedule regular Lynis audits"
    echo "  • Configure Logwatch email delivery"
    echo "  • Set up AIDE cron job for regular checks"
    echo "  • Review and customize alert thresholds"

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Monitoring Tools Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --install-lynis         Install Lynis security auditor
    --run-lynis            Run Lynis audit
    --install-aide         Install AIDE file integrity monitor
    --initialize-aide      Initialize AIDE database
    --run-aide             Run AIDE integrity check
    --install-logwatch     Install Logwatch log analyzer
    --run-logwatch         Generate Logwatch report
    --install-netdata      Install Netdata monitoring
    --install-glances      Install Glances monitor
    --install-metrics      Install metrics collection tools
    --dashboard            Show monitoring dashboard
    --configure-alerts     Configure email alerts
    --complete             Install all monitoring tools
    --help                 Show this help message
    --test                 Run module self-tests

EXAMPLES:
    # Complete setup
    $0 --complete

    # Run security audit
    $0 --run-lynis

    # Show dashboard
    $0 --dashboard

    # Configure alerts
    $0 --configure-alerts admin@example.com

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
export -f install_lynis run_lynis_audit
export -f install_aide configure_aide initialize_aide run_aide_check
export -f install_logwatch configure_logwatch run_logwatch_report
export -f install_netdata configure_netdata
export -f install_glances start_glances_web
export -f install_metrics_tools show_monitoring_dashboard
export -f configure_alerts setup_monitoring_complete

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
source "${SCRIPT_DIR}/../lib/config.sh" 2>/dev/null || true

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --install-lynis)
            install_lynis
            ;;
        --run-lynis)
            run_lynis_audit
            ;;
        --install-aide)
            install_aide
            ;;
        --initialize-aide)
            initialize_aide
            ;;
        --run-aide)
            run_aide_check
            ;;
        --install-logwatch)
            install_logwatch
            ;;
        --run-logwatch)
            run_logwatch_report
            ;;
        --install-netdata)
            install_netdata
            ;;
        --install-glances)
            install_glances
            ;;
        --install-metrics)
            install_metrics_tools
            ;;
        --dashboard)
            show_monitoring_dashboard
            ;;
        --configure-alerts)
            configure_alerts "${2:-}"
            ;;
        --complete)
            setup_monitoring_complete
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running Monitoring Tools module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "Monitoring Tools Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi
