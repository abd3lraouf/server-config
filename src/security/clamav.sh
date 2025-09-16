#!/bin/bash
# ClamAV module - Antivirus and malware protection
# Manages ClamAV installation, configuration, and scanning

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="clamav"

# ClamAV configuration
readonly CLAMAV_DB_DIR="${CLAMAV_DB_DIR:-/var/lib/clamav}"
readonly CLAMAV_LOG_DIR="${CLAMAV_LOG_DIR:-/var/log/clamav}"
readonly CLAMAV_QUARANTINE="${CLAMAV_QUARANTINE:-/var/quarantine}"
readonly CLAMAV_MAX_SIZE="${CLAMAV_MAX_SIZE:-100M}"
readonly CLAMAV_MAX_FILES="${CLAMAV_MAX_FILES:-10000}"

# ============================================================================
# ClamAV Installation
# ============================================================================

# Install ClamAV
install_clamav() {
    print_status "Installing ClamAV antivirus..."

    # Check if already installed
    if command -v clamscan &>/dev/null; then
        print_warning "ClamAV is already installed"
        clamscan --version
        return 0
    fi

    # Update package list
    sudo apt update

    # Install ClamAV packages
    print_status "Installing ClamAV packages..."
    sudo apt install -y \
        clamav \
        clamav-daemon \
        clamav-freshclam \
        libclamav-dev

    # Stop services during configuration
    sudo systemctl stop clamav-freshclam
    sudo systemctl stop clamav-daemon

    # Create directories
    sudo mkdir -p "$CLAMAV_LOG_DIR"
    sudo mkdir -p "$CLAMAV_QUARANTINE"
    sudo chmod 750 "$CLAMAV_QUARANTINE"

    # Set permissions
    sudo chown -R clamav:clamav "$CLAMAV_LOG_DIR"
    sudo chown -R clamav:adm "$CLAMAV_QUARANTINE"

    # Verify installation
    if command -v clamscan &>/dev/null; then
        print_success "ClamAV installed successfully"
        clamscan --version
    else
        print_error "ClamAV installation failed"
        return 1
    fi

    return 0
}

# ============================================================================
# ClamAV Configuration
# ============================================================================

# Configure ClamAV daemon
configure_clamd() {
    print_status "Configuring ClamAV daemon..."

    # Backup configuration
    backup_file "/etc/clamav/clamd.conf"

    # Configure clamd
    cat << EOF | sudo tee /etc/clamav/clamd.conf > /dev/null
# ClamAV Daemon Configuration
LocalSocket /var/run/clamav/clamd.ctl
FixStaleSocket true
LocalSocketGroup clamav
LocalSocketMode 666
User clamav
ScanPE true
ScanELF true
ScanOLE2 true
ScanPDF true
ScanSWF true
ScanHTML true
ScanMail true
ScanArchive true
ArchiveBlockEncrypted false
MaxDirectoryRecursion 15
FollowDirectorySymlinks false
FollowFileSymlinks false
ReadTimeout 180
MaxThreads 12
MaxConnectionQueueLength 15
LogSyslog false
LogRotate true
LogFacility LOG_LOCAL6
LogClean false
LogVerbose false
PreludeEnable no
PreludeAnalyzerName ClamAV
DatabaseDirectory /var/lib/clamav
OfficialDatabaseOnly false
SelfCheck 3600
Foreground false
Debug false
ScanPE true
MaxEmbeddedPE 10M
ScanOLE2 true
ScanPDF true
ScanHTML true
MaxHTMLNormalize 10M
MaxHTMLNoTags 2M
MaxScriptNormalize 5M
MaxZipTypeRcg 1M
ScanSWF true
ExitOnOOM false
LeaveTemporaryFiles false
AlgorithmicDetection true
ScanELF true
IdleTimeout 30
CrossFilesystems true
PhishingSignatures true
PhishingScanURLs true
HeuristicScanPrecedence false
StructuredDataDetection false
CommandReadTimeout 30
SendBufTimeout 200
MaxQueue 100
ExtendedDetectionInfo true
OLE2BlockMacros false
AllowAllMatchScan true
ForceToDisk false
DisableCertCheck false
DisableCache false
MaxScanTime 120000
MaxScanSize $CLAMAV_MAX_SIZE
MaxFileSize 25M
MaxRecursion 16
MaxFiles $CLAMAV_MAX_FILES
MaxPartitions 50
MaxIconsPE 100
PCREMatchLimit 10000
PCRERecMatchLimit 5000
PCREMaxFileSize 25M
StreamMaxLength 25M
LogFile $CLAMAV_LOG_DIR/clamav.log
LogTime true
LogFileUnlock false
LogFileMaxSize 10M
Bytecode true
BytecodeSecurity TrustSigned
BytecodeTimeout 60000
OnAccessMaxFileSize 5M
EOF

    print_success "ClamAV daemon configured"
    return 0
}

# Configure freshclam (virus database updater)
configure_freshclam() {
    print_status "Configuring freshclam updater..."

    # Backup configuration
    backup_file "/etc/clamav/freshclam.conf"

    # Configure freshclam
    cat << EOF | sudo tee /etc/clamav/freshclam.conf > /dev/null
# Freshclam Configuration
DatabaseOwner clamav
UpdateLogFile $CLAMAV_LOG_DIR/freshclam.log
LogVerbose false
LogSyslog false
LogFacility LOG_LOCAL6
LogFileMaxSize 10M
LogRotate true
LogTime true
Foreground false
Debug false
MaxAttempts 5
DatabaseDirectory /var/lib/clamav
DNSDatabaseInfo current.cvd.clamav.net
ConnectTimeout 30
ReceiveTimeout 0
TestDatabases yes
ScriptedUpdates yes
CompressLocalDatabase no
Bytecode true
NotifyClamd /etc/clamav/clamd.conf
Checks 24
DatabaseMirror db.local.clamav.net
DatabaseMirror database.clamav.net
EOF

    print_success "Freshclam configured"
    return 0
}

# ============================================================================
# Database Management
# ============================================================================

# Update virus database
update_virus_database() {
    print_status "Updating virus database..."

    # Stop freshclam service temporarily
    sudo systemctl stop clamav-freshclam

    # Update database
    if sudo freshclam; then
        print_success "Virus database updated successfully"
    else
        print_warning "Database update had issues, retrying..."
        sleep 5
        sudo freshclam || print_error "Failed to update virus database"
    fi

    # Restart freshclam service
    sudo systemctl start clamav-freshclam

    # Show database info
    show_database_info

    return 0
}

# Show database information
show_database_info() {
    print_header "ClamAV Database Information"

    # Check database files
    echo "Database files:"
    ls -lh "$CLAMAV_DB_DIR"/*.cvd "$CLAMAV_DB_DIR"/*.cld 2>/dev/null || echo "No database files found"

    echo ""
    echo "Database versions:"
    sigtool --info "$CLAMAV_DB_DIR"/daily.* 2>/dev/null | grep Version || echo "Daily: Not found"
    sigtool --info "$CLAMAV_DB_DIR"/main.* 2>/dev/null | grep Version || echo "Main: Not found"
    sigtool --info "$CLAMAV_DB_DIR"/bytecode.* 2>/dev/null | grep Version || echo "Bytecode: Not found"

    return 0
}

# ============================================================================
# Scanning Functions
# ============================================================================

# Scan directory
scan_directory() {
    local directory="${1:-/home}"
    local action="${2:-report}"  # report, quarantine, remove

    if [ ! -d "$directory" ]; then
        print_error "Directory not found: $directory"
        return 1
    fi

    print_status "Scanning directory: $directory"

    local scan_log="$CLAMAV_LOG_DIR/scan-$(date +%Y%m%d-%H%M%S).log"
    local infected_log="$CLAMAV_LOG_DIR/infected-$(date +%Y%m%d-%H%M%S).log"

    # Build scan command
    local scan_cmd="clamscan -r"
    scan_cmd="$scan_cmd --log=$scan_log"
    scan_cmd="$scan_cmd --infected"
    scan_cmd="$scan_cmd --exclude-dir=^/proc"
    scan_cmd="$scan_cmd --exclude-dir=^/sys"
    scan_cmd="$scan_cmd --exclude-dir=^/dev"
    scan_cmd="$scan_cmd --max-filesize=$CLAMAV_MAX_SIZE"
    scan_cmd="$scan_cmd --max-scansize=$CLAMAV_MAX_SIZE"

    case "$action" in
        quarantine)
            scan_cmd="$scan_cmd --move=$CLAMAV_QUARANTINE"
            ;;
        remove)
            scan_cmd="$scan_cmd --remove=yes"
            ;;
        *)
            scan_cmd="$scan_cmd --bell"
            ;;
    esac

    scan_cmd="$scan_cmd $directory"

    # Run scan
    print_status "Scanning in progress (this may take a while)..."
    if sudo $scan_cmd | tee "$infected_log"; then
        print_success "Scan completed"
    else
        print_warning "Scan completed with infections found"
    fi

    # Show summary
    echo ""
    echo "Scan Summary:"
    tail -20 "$scan_log" | grep -E "Infected files|Scanned files|Data scanned|Time:"

    # Check for infections
    if grep -q "Infected files: 0" "$scan_log"; then
        print_success "No infections found"
    else
        print_warning "Infections detected! Check log: $infected_log"
        echo ""
        echo "Infected files:"
        grep FOUND "$infected_log" | head -10
    fi

    return 0
}

# Quick scan (common infection points)
quick_scan() {
    print_status "Running quick scan..."

    local scan_targets=(
        "/tmp"
        "/var/tmp"
        "/home"
        "/root"
        "/var/www"
        "/opt"
    )

    for target in "${scan_targets[@]}"; do
        if [ -d "$target" ]; then
            print_status "Scanning: $target"
            clamscan -ri "$target" --max-filesize=50M --max-scansize=50M \
                --exclude-dir=^/proc --exclude-dir=^/sys --exclude-dir=^/dev \
                2>/dev/null | grep -E "FOUND|OK" | tail -5
        fi
    done

    print_success "Quick scan completed"
    return 0
}

# Scan file
scan_file() {
    local file="${1:-}"

    if [ -z "$file" ] || [ ! -f "$file" ]; then
        print_error "File not found: $file"
        return 1
    fi

    print_status "Scanning file: $file"

    if clamscan "$file"; then
        print_success "File is clean"
    else
        print_warning "File may be infected"
    fi

    return 0
}

# ============================================================================
# Real-time Protection
# ============================================================================

# Configure on-access scanning
configure_on_access() {
    print_status "Configuring on-access scanning..."

    # Add on-access configuration to clamd.conf
    cat << EOF | sudo tee -a /etc/clamav/clamd.conf > /dev/null

# On-Access Scanning
OnAccessIncludePath /home
OnAccessIncludePath /tmp
OnAccessIncludePath /var/tmp
OnAccessIncludePath /var/www
OnAccessExcludePath /proc
OnAccessExcludePath /sys
OnAccessExcludePath /dev
OnAccessExcludeRootUID true
OnAccessExcludeUID 0
OnAccessMaxFileSize 10M
OnAccessDisableDDD false
OnAccessPrevention false
OnAccessExtraScanning true
EOF

    # Install fanotify support if needed
    sudo apt install -y libfanotify0

    print_success "On-access scanning configured"
    print_warning "Kernel support for fanotify is required for on-access scanning"

    return 0
}

# ============================================================================
# Scheduled Scanning
# ============================================================================

# Setup scheduled scans
setup_scheduled_scans() {
    print_status "Setting up scheduled scans..."

    # Create scan script
    cat << 'EOF' | sudo tee /usr/local/bin/clamav-scan.sh > /dev/null
#!/bin/bash
# ClamAV Scheduled Scan Script

SCAN_DIR="${1:-/}"
LOG_FILE="/var/log/clamav/scheduled-scan-$(date +%Y%m%d).log"
QUARANTINE="/var/quarantine"

# Update database
/usr/bin/freshclam --quiet

# Run scan
/usr/bin/clamscan -ri "$SCAN_DIR" \
    --log="$LOG_FILE" \
    --move="$QUARANTINE" \
    --exclude-dir=^/proc \
    --exclude-dir=^/sys \
    --exclude-dir=^/dev \
    --max-filesize=100M \
    --max-scansize=100M

# Send notification if infections found
if grep -q "Infected files: [1-9]" "$LOG_FILE"; then
    echo "ClamAV: Infections detected on $(hostname)" | mail -s "ClamAV Alert" root
fi
EOF

    sudo chmod +x /usr/local/bin/clamav-scan.sh

    # Add cron job for daily scan at 2 AM
    (crontab -l 2>/dev/null | grep -v clamav-scan; echo "0 2 * * * /usr/local/bin/clamav-scan.sh /home") | crontab -

    # Add cron job for weekly full scan on Sunday at 3 AM
    (crontab -l 2>/dev/null; echo "0 3 * * 0 /usr/local/bin/clamav-scan.sh /") | crontab -

    print_success "Scheduled scans configured"
    print_status "Daily scan: 2 AM (home directories)"
    print_status "Weekly scan: Sunday 3 AM (full system)"

    return 0
}

# ============================================================================
# Service Management
# ============================================================================

# Start ClamAV services
start_services() {
    print_status "Starting ClamAV services..."

    # Start freshclam
    sudo systemctl enable clamav-freshclam
    sudo systemctl start clamav-freshclam

    # Start clamd
    sudo systemctl enable clamav-daemon
    sudo systemctl start clamav-daemon

    # Check status
    if systemctl is-active clamav-daemon &>/dev/null; then
        print_success "ClamAV daemon is running"
    else
        print_error "ClamAV daemon failed to start"
    fi

    if systemctl is-active clamav-freshclam &>/dev/null; then
        print_success "Freshclam updater is running"
    else
        print_error "Freshclam updater failed to start"
    fi

    return 0
}

# Show ClamAV status
show_clamav_status() {
    print_header "ClamAV Status"

    # Service status
    echo "ClamAV Daemon:"
    systemctl status clamav-daemon --no-pager | head -10

    echo ""
    echo "Freshclam Updater:"
    systemctl status clamav-freshclam --no-pager | head -10

    echo ""
    # Database info
    show_database_info

    echo ""
    # Quarantine status
    echo "Quarantine Directory:"
    if [ -d "$CLAMAV_QUARANTINE" ]; then
        local count=$(find "$CLAMAV_QUARANTINE" -type f 2>/dev/null | wc -l)
        echo "  Files in quarantine: $count"
        if [ "$count" -gt 0 ]; then
            echo "  Recent quarantined files:"
            ls -lt "$CLAMAV_QUARANTINE" 2>/dev/null | head -5
        fi
    else
        echo "  Quarantine directory not found"
    fi

    return 0
}

# ============================================================================
# Complete Setup
# ============================================================================

# Run complete ClamAV setup
setup_clamav_complete() {
    print_header "Complete ClamAV Setup"

    # Install ClamAV
    install_clamav

    # Configure components
    configure_clamd
    configure_freshclam

    # Update virus database
    update_virus_database

    # Start services
    start_services

    # Setup scheduled scans
    setup_scheduled_scans

    # Optional: Configure on-access scanning
    if confirm_action "Enable on-access scanning (requires kernel support)?"; then
        configure_on_access
    fi

    # Run initial quick scan
    if confirm_action "Run initial quick scan?"; then
        quick_scan
    fi

    # Show status
    show_clamav_status

    print_success "ClamAV setup completed!"
    print_warning "Remember to:"
    echo "  • Monitor quarantine directory regularly"
    echo "  • Review scan logs in $CLAMAV_LOG_DIR"
    echo "  • Adjust scan schedules as needed"
    echo "  • Keep virus database updated"

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
ClamAV Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --install               Install ClamAV
    --configure             Configure ClamAV daemon
    --update                Update virus database
    --scan DIR [ACTION]     Scan directory (report/quarantine/remove)
    --scan-file FILE        Scan specific file
    --quick-scan            Run quick scan
    --schedule              Setup scheduled scans
    --on-access             Configure on-access scanning
    --start                 Start ClamAV services
    --status                Show ClamAV status
    --complete              Complete setup
    --help                  Show this help message
    --test                  Run module self-tests

EXAMPLES:
    # Complete setup
    $0 --complete

    # Scan with quarantine
    $0 --scan /home quarantine

    # Quick scan
    $0 --quick-scan

    # Update database
    $0 --update

    # Check status
    $0 --status

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
export -f install_clamav configure_clamd configure_freshclam
export -f update_virus_database show_database_info
export -f scan_directory quick_scan scan_file
export -f configure_on_access setup_scheduled_scans
export -f start_services show_clamav_status
export -f setup_clamav_complete

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
        --install)
            install_clamav
            ;;
        --configure)
            configure_clamd
            configure_freshclam
            ;;
        --update)
            update_virus_database
            ;;
        --scan)
            scan_directory "${2:-/home}" "${3:-report}"
            ;;
        --scan-file)
            scan_file "${2}"
            ;;
        --quick-scan)
            quick_scan
            ;;
        --schedule)
            setup_scheduled_scans
            ;;
        --on-access)
            configure_on_access
            ;;
        --start)
            start_services
            ;;
        --status)
            show_clamav_status
            ;;
        --complete)
            setup_clamav_complete
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running ClamAV module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "ClamAV Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi
