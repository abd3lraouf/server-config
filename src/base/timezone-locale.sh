#!/bin/bash
# Timezone and Locale module - System timezone, locale, and NTP configuration
# Manages timezone settings, locale configuration, and time synchronization

# Script metadata
readonly MODULE_VERSION="1.0.0"
readonly MODULE_NAME="timezone-locale"

# Configuration defaults
readonly DEFAULT_TIMEZONE="${DEFAULT_TIMEZONE:-UTC}"
readonly DEFAULT_LOCALE="${DEFAULT_LOCALE:-en_US.UTF-8}"
readonly NTP_SERVERS="${NTP_SERVERS:-0.ubuntu.pool.ntp.org 1.ubuntu.pool.ntp.org}"

# ============================================================================
# Timezone Configuration
# ============================================================================

# Set system timezone
set_timezone() {
    local timezone="${1:-$DEFAULT_TIMEZONE}"

    print_status "Setting timezone to: $timezone"

    # Validate timezone exists
    if [ ! -f "/usr/share/zoneinfo/$timezone" ]; then
        print_error "Invalid timezone: $timezone"
        print_status "Use 'timedatectl list-timezones' to see available timezones"
        return 1
    fi

    # Set timezone using timedatectl
    if sudo timedatectl set-timezone "$timezone"; then
        print_success "Timezone set to: $timezone"

        # Also update /etc/timezone for compatibility
        echo "$timezone" | sudo tee /etc/timezone > /dev/null

        # Update /etc/localtime symlink
        sudo ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime

        # Show current time
        print_status "Current time: $(date)"
    else
        print_error "Failed to set timezone"
        return 1
    fi

    return 0
}

# Get current timezone
get_timezone() {
    print_header "Current Timezone Settings"

    # Show timezone info
    timedatectl show --property=Timezone --value

    echo ""
    echo "Detailed timezone information:"
    timedatectl status

    echo ""
    echo "Current date and time:"
    date

    return 0
}

# Interactive timezone selection
select_timezone_interactive() {
    print_header "Interactive Timezone Selection"

    # Get continent/region
    echo "Select your continent/region:"
    local regions=(
        "Africa"
        "America"
        "Antarctica"
        "Arctic"
        "Asia"
        "Atlantic"
        "Australia"
        "Europe"
        "Indian"
        "Pacific"
        "UTC"
    )

    local i=1
    for region in "${regions[@]}"; do
        echo "  $i) $region"
        ((i++))
    done

    read -p "Select region [1-${#regions[@]}]: " region_choice

    if [ "$region_choice" -lt 1 ] || [ "$region_choice" -gt ${#regions[@]} ]; then
        print_error "Invalid selection"
        return 1
    fi

    local selected_region="${regions[$((region_choice-1))]}"

    if [ "$selected_region" = "UTC" ]; then
        set_timezone "UTC"
        return 0
    fi

    # Get city
    echo ""
    echo "Available cities in $selected_region:"
    local cities=($(timedatectl list-timezones | grep "^$selected_region/" | sed "s|^$selected_region/||" | head -20))

    i=1
    for city in "${cities[@]}"; do
        echo "  $i) $city"
        ((i++))
    done

    echo "  0) Show all cities"

    read -p "Select city [0-${#cities[@]}]: " city_choice

    if [ "$city_choice" = "0" ]; then
        # Show all cities
        timedatectl list-timezones | grep "^$selected_region/"
        read -p "Enter city name: " city_name
        set_timezone "$selected_region/$city_name"
    elif [ "$city_choice" -ge 1 ] && [ "$city_choice" -le ${#cities[@]} ]; then
        local selected_city="${cities[$((city_choice-1))]}"
        set_timezone "$selected_region/$selected_city"
    else
        print_error "Invalid selection"
        return 1
    fi

    return 0
}

# ============================================================================
# Locale Configuration
# ============================================================================

# Set system locale
set_locale() {
    local locale="${1:-$DEFAULT_LOCALE}"

    print_status "Setting locale to: $locale"

    # Generate locale if not available
    if ! locale -a 2>/dev/null | grep -q "^$locale"; then
        print_status "Generating locale: $locale"

        # Extract language code
        local lang_code="${locale%.*}"

        # Add to locale.gen
        sudo sed -i "s/^# *$lang_code/$lang_code/" /etc/locale.gen

        # Generate locales
        sudo locale-gen
    fi

    # Set locale
    sudo update-locale LANG="$locale"
    sudo update-locale LANGUAGE="$locale"
    sudo update-locale LC_ALL="$locale"

    # Export for current session
    export LANG="$locale"
    export LANGUAGE="$locale"
    export LC_ALL="$locale"

    print_success "Locale set to: $locale"
    print_warning "You may need to logout and login for changes to take full effect"

    return 0
}

# Get current locale
get_locale() {
    print_header "Current Locale Settings"

    echo "Active locale:"
    locale

    echo ""
    echo "Available locales:"
    locale -a | head -20
    echo "..."

    echo ""
    echo "Default system locale:"
    cat /etc/default/locale

    return 0
}

# Generate additional locales
generate_locales() {
    print_status "Generating additional locales..."

    # Common locales to generate
    local locales=(
        "en_US.UTF-8"
        "en_GB.UTF-8"
        "de_DE.UTF-8"
        "fr_FR.UTF-8"
        "es_ES.UTF-8"
        "it_IT.UTF-8"
        "pt_BR.UTF-8"
        "ru_RU.UTF-8"
        "ja_JP.UTF-8"
        "zh_CN.UTF-8"
    )

    for locale in "${locales[@]}"; do
        local lang_code="${locale%.*}"
        if ! locale -a 2>/dev/null | grep -q "^$locale"; then
            print_status "Generating: $locale"
            sudo sed -i "s/^# *$lang_code UTF-8/$lang_code UTF-8/" /etc/locale.gen
        fi
    done

    # Regenerate all locales
    sudo locale-gen

    print_success "Locales generated"
    return 0
}

# ============================================================================
# NTP Configuration
# ============================================================================

# Configure NTP time synchronization
configure_ntp() {
    print_status "Configuring NTP time synchronization..."

    # Check if systemd-timesyncd is available
    if systemctl list-unit-files | grep -q systemd-timesyncd; then
        configure_systemd_timesyncd
    else
        # Fall back to ntpd or chrony
        configure_ntp_daemon
    fi

    return 0
}

# Configure systemd-timesyncd
configure_systemd_timesyncd() {
    print_status "Configuring systemd-timesyncd..."

    # Backup configuration
    backup_file "/etc/systemd/timesyncd.conf"

    # Configure NTP servers
    cat << EOF | sudo tee /etc/systemd/timesyncd.conf > /dev/null
# systemd-timesyncd configuration
[Time]
NTP=$NTP_SERVERS
FallbackNTP=0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org 3.pool.ntp.org
RootDistanceMaxSec=5
PollIntervalMinSec=32
PollIntervalMaxSec=2048
EOF

    # Enable and restart service
    sudo systemctl enable systemd-timesyncd
    sudo systemctl restart systemd-timesyncd

    # Enable NTP
    sudo timedatectl set-ntp true

    print_success "systemd-timesyncd configured"

    # Show status
    timedatectl timesync-status

    return 0
}

# Configure traditional NTP daemon
configure_ntp_daemon() {
    print_status "Configuring NTP daemon..."

    # Install ntp if not present
    if ! command -v ntpd &>/dev/null; then
        sudo apt update
        sudo apt install -y ntp
    fi

    # Backup configuration
    backup_file "/etc/ntp.conf"

    # Configure NTP
    cat << EOF | sudo tee /etc/ntp.conf > /dev/null
# NTP Configuration
driftfile /var/lib/ntp/ntp.drift
leapfile /usr/share/zoneinfo/leap-seconds.list

# Statistics
statistics loopstats peerstats clockstats
filegen loopstats file loopstats type day enable
filegen peerstats file peerstats type day enable
filegen clockstats file clockstats type day enable

# NTP Servers
EOF

    # Add NTP servers
    for server in $NTP_SERVERS; do
        echo "server $server iburst" | sudo tee -a /etc/ntp.conf > /dev/null
    done

    # Add pool servers as fallback
    cat << EOF | sudo tee -a /etc/ntp.conf > /dev/null

# Fallback servers
pool 0.pool.ntp.org iburst
pool 1.pool.ntp.org iburst
pool 2.pool.ntp.org iburst
pool 3.pool.ntp.org iburst

# Access restrictions
restrict default nomodify notrap nopeer noquery
restrict 127.0.0.1
restrict ::1

# Allow LAN clients (adjust as needed)
restrict 192.168.0.0 mask 255.255.0.0 nomodify notrap
restrict 10.0.0.0 mask 255.0.0.0 nomodify notrap
EOF

    # Restart NTP service
    sudo systemctl enable ntp
    sudo systemctl restart ntp

    print_success "NTP daemon configured"

    # Show status
    ntpq -p

    return 0
}

# Check time synchronization status
check_time_sync() {
    print_header "Time Synchronization Status"

    # Check if time is synchronized
    if timedatectl status | grep -q "System clock synchronized: yes"; then
        print_success "System clock is synchronized"
    else
        print_warning "System clock is not synchronized"
    fi

    echo ""
    echo "Time synchronization details:"
    timedatectl status

    # Check NTP service status
    echo ""
    if systemctl is-active systemd-timesyncd &>/dev/null; then
        echo "systemd-timesyncd status:"
        systemctl status systemd-timesyncd --no-pager | head -10
        echo ""
        timedatectl timesync-status
    elif systemctl is-active ntp &>/dev/null; then
        echo "NTP daemon status:"
        systemctl status ntp --no-pager | head -10
        echo ""
        ntpq -p
    elif systemctl is-active chrony &>/dev/null; then
        echo "Chrony status:"
        chronyc tracking
    fi

    return 0
}

# ============================================================================
# Keyboard Configuration
# ============================================================================

# Configure keyboard layout
configure_keyboard() {
    local layout="${1:-us}"
    local model="${2:-pc105}"
    local variant="${3:-}"

    print_status "Configuring keyboard layout: $layout"

    # Configure console keyboard
    cat << EOF | sudo tee /etc/default/keyboard > /dev/null
# Keyboard configuration
XKBMODEL="$model"
XKBLAYOUT="$layout"
XKBVARIANT="$variant"
XKBOPTIONS=""
BACKSPACE="guess"
EOF

    # Apply settings
    sudo setupcon

    # For X11 if available
    if command -v setxkbmap &>/dev/null; then
        setxkbmap "$layout" "$variant"
    fi

    print_success "Keyboard layout set to: $layout"
    return 0
}

# ============================================================================
# Complete Setup
# ============================================================================

# Run complete timezone and locale setup
setup_timezone_locale_complete() {
    print_header "Complete Timezone and Locale Setup"

    # Configure timezone
    print_status "Configure timezone..."
    if confirm_action "Use interactive timezone selection?"; then
        select_timezone_interactive
    else
        read -p "Enter timezone (e.g., America/New_York): " tz
        set_timezone "${tz:-UTC}"
    fi

    echo ""

    # Configure locale
    print_status "Configure locale..."
    read -p "Enter locale (default: $DEFAULT_LOCALE): " locale
    set_locale "${locale:-$DEFAULT_LOCALE}"

    if confirm_action "Generate additional locales?"; then
        generate_locales
    fi

    echo ""

    # Configure NTP
    print_status "Configure time synchronization..."
    configure_ntp

    echo ""

    # Configure keyboard if needed
    if confirm_action "Configure keyboard layout?"; then
        read -p "Enter keyboard layout (default: us): " layout
        configure_keyboard "${layout:-us}"
    fi

    echo ""

    # Show final status
    get_timezone
    echo ""
    get_locale
    echo ""
    check_time_sync

    print_success "Timezone and locale setup completed!"

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Timezone and Locale Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --set-timezone TZ       Set timezone (e.g., America/New_York)
    --get-timezone          Show current timezone
    --select-timezone       Interactive timezone selection
    --set-locale LOCALE     Set locale (e.g., en_US.UTF-8)
    --get-locale            Show current locale
    --generate-locales      Generate common locales
    --configure-ntp         Configure NTP synchronization
    --check-time            Check time synchronization status
    --keyboard LAYOUT       Configure keyboard layout
    --complete              Complete setup wizard
    --help                  Show this help message
    --test                  Run module self-tests

EXAMPLES:
    # Set timezone
    $0 --set-timezone America/New_York

    # Interactive timezone selection
    $0 --select-timezone

    # Set locale
    $0 --set-locale en_US.UTF-8

    # Configure NTP
    $0 --configure-ntp

    # Complete setup
    $0 --complete

ENVIRONMENT VARIABLES:
    DEFAULT_TIMEZONE        Default timezone (UTC)
    DEFAULT_LOCALE          Default locale (en_US.UTF-8)
    NTP_SERVERS            Space-separated NTP servers

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
export -f set_timezone get_timezone select_timezone_interactive
export -f set_locale get_locale generate_locales
export -f configure_ntp configure_systemd_timesyncd configure_ntp_daemon
export -f check_time_sync configure_keyboard
export -f setup_timezone_locale_complete

# Source required libraries
if [ -z "${SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/backup.sh" 2>/dev/null || true

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --set-timezone)
            set_timezone "${2:-$DEFAULT_TIMEZONE}"
            ;;
        --get-timezone)
            get_timezone
            ;;
        --select-timezone)
            select_timezone_interactive
            ;;
        --set-locale)
            set_locale "${2:-$DEFAULT_LOCALE}"
            ;;
        --get-locale)
            get_locale
            ;;
        --generate-locales)
            generate_locales
            ;;
        --configure-ntp)
            configure_ntp
            ;;
        --check-time)
            check_time_sync
            ;;
        --keyboard)
            configure_keyboard "${2:-us}" "${3:-pc105}" "${4:-}"
            ;;
        --complete)
            setup_timezone_locale_complete
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running Timezone and Locale module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "Timezone and Locale Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi