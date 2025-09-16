#!/bin/bash
# Main Menu System module - Full-featured advanced menu interface
# Provides comprehensive menu navigation with categories and progress tracking

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="main-menu"

# Configuration
[[ -z "${MENU_CONFIG_DIR:-}" ]] && readonly MENU_CONFIG_DIR="/etc/server-config/menu"
[[ -z "${MENU_STATE_FILE:-}" ]] && readonly MENU_STATE_FILE="$MENU_CONFIG_DIR/state.json"
[[ -z "${MENU_HISTORY_FILE:-}" ]] && readonly MENU_HISTORY_FILE="$MENU_CONFIG_DIR/history.log"
[[ -z "${MENU_PRESETS_DIR:-}" ]] && readonly MENU_PRESETS_DIR="$MENU_CONFIG_DIR/presets"

# Colors and formatting
readonly COLOR_HEADER="\033[1;36m"    # Cyan bold
readonly COLOR_CATEGORY="\033[1;35m"  # Magenta bold
readonly COLOR_OPTION="\033[0;37m"    # White
readonly COLOR_SUCCESS="\033[0;32m"   # Green
readonly COLOR_WARNING="\033[0;33m"   # Yellow
readonly COLOR_ERROR="\033[0;31m"     # Red
readonly COLOR_INFO="\033[0;34m"      # Blue
readonly COLOR_RESET="\033[0m"        # Reset

# Menu configuration
declare -A MENU_CATEGORIES
declare -A MENU_OPTIONS
declare -A MENU_DESCRIPTIONS
declare -A MENU_STATUS
declare -A MENU_REQUIREMENTS

# ============================================================================
# Menu Setup
# ============================================================================

# Initialize menu system
initialize_menu() {
    # Create config directories
    sudo mkdir -p "$MENU_CONFIG_DIR"
    sudo mkdir -p "$MENU_PRESETS_DIR"

    # Initialize state file if not exists
    if [ ! -f "$MENU_STATE_FILE" ]; then
        echo '{"completed": [], "in_progress": null, "last_run": null}' | sudo tee "$MENU_STATE_FILE" > /dev/null
    fi

    # Initialize history file
    if [ ! -f "$MENU_HISTORY_FILE" ]; then
        sudo touch "$MENU_HISTORY_FILE"
    fi

    # Load menu definitions
    load_menu_definitions
}

# Load menu definitions
load_menu_definitions() {
    # Base Configuration Category
    MENU_CATEGORIES["1"]="Base Configuration"

    MENU_OPTIONS["1.1"]="System Updates"
    MENU_DESCRIPTIONS["1.1"]="Update system packages and configure automatic updates"
    MENU_REQUIREMENTS["1.1"]=""

    MENU_OPTIONS["1.2"]="Shell Setup (Zsh + Oh-My-Zsh)"
    MENU_DESCRIPTIONS["1.2"]="Install and configure Zsh with Oh-My-Zsh and Powerlevel10k"
    MENU_REQUIREMENTS["1.1"]="1.1"

    MENU_OPTIONS["1.3"]="Development Tools"
    MENU_DESCRIPTIONS["1.3"]="Install NVM, Node.js, and development utilities"
    MENU_REQUIREMENTS["1.3"]="1.1"

    MENU_OPTIONS["1.4"]="User Management"
    MENU_DESCRIPTIONS["1.4"]="Configure users, groups, and sudo access"
    MENU_REQUIREMENTS["1.4"]=""

    MENU_OPTIONS["1.5"]="Timezone & Locale"
    MENU_DESCRIPTIONS["1.5"]="Configure system timezone, locale, and NTP"
    MENU_REQUIREMENTS["1.5"]=""

    # Security Configuration Category
    MENU_CATEGORIES["2"]="Security Configuration"

    MENU_OPTIONS["2.1"]="SSH Hardening"
    MENU_DESCRIPTIONS["2.1"]="Harden SSH configuration and manage keys"
    MENU_REQUIREMENTS["2.1"]=""

    MENU_OPTIONS["2.2"]="Firewall (UFW)"
    MENU_DESCRIPTIONS["2.2"]="Configure UFW firewall with Docker support"
    MENU_REQUIREMENTS["2.2"]=""

    MENU_OPTIONS["2.3"]="Fail2ban"
    MENU_DESCRIPTIONS["2.3"]="Install and configure Fail2ban intrusion prevention"
    MENU_REQUIREMENTS["2.3"]="2.2"

    MENU_OPTIONS["2.4"]="CrowdSec"
    MENU_DESCRIPTIONS["2.4"]="Install CrowdSec collaborative IPS"
    MENU_REQUIREMENTS["2.4"]="2.2"

    MENU_OPTIONS["2.5"]="System Hardening"
    MENU_DESCRIPTIONS["2.5"]="Apply CIS benchmark hardening"
    MENU_REQUIREMENTS["2.5"]=""

    MENU_OPTIONS["2.6"]="AIDE File Integrity"
    MENU_DESCRIPTIONS["2.6"]="Setup AIDE file integrity monitoring"
    MENU_REQUIREMENTS["2.6"]=""

    MENU_OPTIONS["2.7"]="ClamAV Antivirus"
    MENU_DESCRIPTIONS["2.7"]="Install and configure ClamAV"
    MENU_REQUIREMENTS["2.7"]=""

    # Network Services Category
    MENU_CATEGORIES["3"]="Network Services"

    MENU_OPTIONS["3.1"]="Tailscale VPN"
    MENU_DESCRIPTIONS["3.1"]="Install and configure Tailscale mesh VPN"
    MENU_REQUIREMENTS["3.1"]="2.2"

    MENU_OPTIONS["3.2"]="Cloudflare Tunnel"
    MENU_DESCRIPTIONS["3.2"]="Setup Cloudflare Tunnel for secure access"
    MENU_REQUIREMENTS["3.2"]="2.2"

    MENU_OPTIONS["3.3"]="Traefik Proxy"
    MENU_DESCRIPTIONS["3.3"]="Install Traefik reverse proxy with SSL"
    MENU_REQUIREMENTS["3.3"]="4.1"

    # Container Platforms Category
    MENU_CATEGORIES["4"]="Container Platforms"

    MENU_OPTIONS["4.1"]="Docker"
    MENU_DESCRIPTIONS["4.1"]="Install Docker and Docker Compose"
    MENU_REQUIREMENTS["4.1"]=""

    MENU_OPTIONS["4.2"]="Podman"
    MENU_DESCRIPTIONS["4.2"]="Install Podman (rootless containers)"
    MENU_REQUIREMENTS["4.2"]=""

    MENU_OPTIONS["4.3"]="Coolify"
    MENU_DESCRIPTIONS["4.3"]="Install Coolify PaaS platform"
    MENU_REQUIREMENTS["4.3"]="4.1"

    # Monitoring & Compliance Category
    MENU_CATEGORIES["5"]="Monitoring & Compliance"

    MENU_OPTIONS["5.1"]="Monitoring Tools"
    MENU_DESCRIPTIONS["5.1"]="Install system monitoring tools"
    MENU_REQUIREMENTS["5.1"]=""

    MENU_OPTIONS["5.2"]="Lynis Auditing"
    MENU_DESCRIPTIONS["5.2"]="Setup Lynis security auditing"
    MENU_REQUIREMENTS["5.2"]=""

    MENU_OPTIONS["5.3"]="Logwatch"
    MENU_DESCRIPTIONS["5.3"]="Configure Logwatch log analysis"
    MENU_REQUIREMENTS["5.3"]=""

    MENU_OPTIONS["5.4"]="Compliance Reporting"
    MENU_DESCRIPTIONS["5.4"]="Setup compliance checking (CIS, PCI-DSS, etc.)"
    MENU_REQUIREMENTS["5.4"]="5.2"

    # Complete Setups Category
    MENU_CATEGORIES["6"]="Complete Setups"

    MENU_OPTIONS["6.1"]="Basic Server Setup"
    MENU_DESCRIPTIONS["6.1"]="Complete basic server configuration"
    MENU_REQUIREMENTS["6.1"]=""

    MENU_OPTIONS["6.2"]="Development Environment"
    MENU_DESCRIPTIONS["6.2"]="Setup complete development environment"
    MENU_REQUIREMENTS["6.2"]=""

    MENU_OPTIONS["6.3"]="Zero Trust Security"
    MENU_DESCRIPTIONS["6.3"]="Deploy complete Zero Trust architecture"
    MENU_REQUIREMENTS["6.3"]=""

    MENU_OPTIONS["6.4"]="Container Platform"
    MENU_DESCRIPTIONS["6.4"]="Setup Docker/Podman with orchestration"
    MENU_REQUIREMENTS["6.4"]=""

    # Utilities Category
    MENU_CATEGORIES["7"]="Utilities"

    MENU_OPTIONS["7.1"]="Generate Documentation"
    MENU_DESCRIPTIONS["7.1"]="Generate system documentation"
    MENU_REQUIREMENTS["7.1"]=""

    MENU_OPTIONS["7.2"]="Emergency Recovery"
    MENU_DESCRIPTIONS["7.2"]="Access emergency recovery tools"
    MENU_REQUIREMENTS["7.2"]=""

    MENU_OPTIONS["7.3"]="System Backup"
    MENU_DESCRIPTIONS["7.3"]="Backup system configuration"
    MENU_REQUIREMENTS["7.3"]=""

    MENU_OPTIONS["7.4"]="View Logs"
    MENU_DESCRIPTIONS["7.4"]="View system and security logs"
    MENU_REQUIREMENTS["7.4"]=""
}

# ============================================================================
# Menu Display
# ============================================================================

# Display main menu
display_main_menu() {
    clear
    echo -e "${COLOR_HEADER}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║              Ubuntu Server Configuration - Main Menu               ║"
    echo "║                         Version $MODULE_VERSION                    ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"

    # Display system info
    display_system_info

    echo ""
    echo -e "${COLOR_INFO}Select a category or option:${COLOR_RESET}"
    echo ""

    # Display categories and options
    for category_num in $(echo "${!MENU_CATEGORIES[@]}" | tr ' ' '\n' | sort -n); do
        echo -e "${COLOR_CATEGORY}━━━ ${category_num}. ${MENU_CATEGORIES[$category_num]} ━━━${COLOR_RESET}"

        # Display options in this category
        for option_key in $(echo "${!MENU_OPTIONS[@]}" | tr ' ' '\n' | sort -V); do
            if [[ $option_key == ${category_num}.* ]]; then
                display_menu_option "$option_key"
            fi
        done
        echo ""
    done

    # Display special options
    echo -e "${COLOR_CATEGORY}━━━ Special Options ━━━${COLOR_RESET}"
    echo -e "${COLOR_OPTION}  P) Progress Report${COLOR_RESET} - View installation progress"
    echo -e "${COLOR_OPTION}  S) System Status${COLOR_RESET} - Check system services"
    echo -e "${COLOR_OPTION}  H) History${COLOR_RESET} - View command history"
    echo -e "${COLOR_OPTION}  R) Reset${COLOR_RESET} - Reset menu state"
    echo -e "${COLOR_OPTION}  Q) Quit${COLOR_RESET} - Exit menu"
    echo ""
}

# Display individual menu option
display_menu_option() {
    local option_key="$1"
    local option_name="${MENU_OPTIONS[$option_key]}"
    local description="${MENU_DESCRIPTIONS[$option_key]}"
    local requirements="${MENU_REQUIREMENTS[$option_key]}"
    local status_icon=""
    local status_color=""

    # Check completion status
    if is_option_completed "$option_key"; then
        status_icon="✓"
        status_color="${COLOR_SUCCESS}"
    elif is_option_in_progress "$option_key"; then
        status_icon="⟳"
        status_color="${COLOR_WARNING}"
    elif [ -n "$requirements" ] && ! is_option_completed "$requirements"; then
        status_icon="🔒"
        status_color="${COLOR_ERROR}"
    else
        status_icon=" "
        status_color="${COLOR_OPTION}"
    fi

    echo -e "${status_color}  ${status_icon} ${option_key}) ${option_name}${COLOR_RESET}"
    echo -e "      ${COLOR_INFO}${description}${COLOR_RESET}"

    # Show requirements if not met
    if [ -n "$requirements" ] && ! is_option_completed "$requirements"; then
        echo -e "      ${COLOR_WARNING}Requires: ${MENU_OPTIONS[$requirements]}${COLOR_RESET}"
    fi
}

# Display system info
display_system_info() {
    echo -e "${COLOR_INFO}System Information:${COLOR_RESET}"
    echo "  Hostname: $(hostname -f)"
    echo "  OS: $(lsb_release -ds 2>/dev/null || echo 'Unknown')"
    echo "  Kernel: $(uname -r)"
    echo "  Uptime: $(uptime -p)"
    echo "  Load: $(uptime | awk -F'load average:' '{print $2}')"
}

# ============================================================================
# Menu State Management
# ============================================================================

# Check if option is completed
is_option_completed() {
    local option_key="$1"

    if [ -f "$MENU_STATE_FILE" ]; then
        jq -e ".completed[] | select(. == \"$option_key\")" "$MENU_STATE_FILE" &>/dev/null
        return $?
    fi

    return 1
}

# Check if option is in progress
is_option_in_progress() {
    local option_key="$1"

    if [ -f "$MENU_STATE_FILE" ]; then
        local in_progress=$(jq -r '.in_progress' "$MENU_STATE_FILE")
        [ "$in_progress" = "$option_key" ]
        return $?
    fi

    return 1
}

# Mark option as completed
mark_completed() {
    local option_key="$1"

    if [ -f "$MENU_STATE_FILE" ]; then
        local temp_file=$(mktemp)
        jq ".completed += [\"$option_key\"] | .completed |= unique | .in_progress = null" "$MENU_STATE_FILE" > "$temp_file"
        sudo mv "$temp_file" "$MENU_STATE_FILE"
    fi

    # Log to history
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Completed: ${MENU_OPTIONS[$option_key]}" | sudo tee -a "$MENU_HISTORY_FILE" > /dev/null
}

# Mark option as in progress
mark_in_progress() {
    local option_key="$1"

    if [ -f "$MENU_STATE_FILE" ]; then
        local temp_file=$(mktemp)
        jq ".in_progress = \"$option_key\"" "$MENU_STATE_FILE" > "$temp_file"
        sudo mv "$temp_file" "$MENU_STATE_FILE"
    fi

    # Log to history
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Started: ${MENU_OPTIONS[$option_key]}" | sudo tee -a "$MENU_HISTORY_FILE" > /dev/null
}

# Reset menu state
reset_menu_state() {
    echo '{"completed": [], "in_progress": null, "last_run": null}' | sudo tee "$MENU_STATE_FILE" > /dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Menu state reset" | sudo tee -a "$MENU_HISTORY_FILE" > /dev/null
    print_success "Menu state has been reset"
}

# ============================================================================
# Option Execution
# ============================================================================

# Execute menu option
execute_option() {
    local option_key="$1"

    # Check requirements
    local requirements="${MENU_REQUIREMENTS[$option_key]}"
    if [ -n "$requirements" ] && ! is_option_completed "$requirements"; then
        print_error "Requirements not met. Please complete: ${MENU_OPTIONS[$requirements]}"
        read -p "Press Enter to continue..."
        return 1
    fi

    # Mark as in progress
    mark_in_progress "$option_key"

    # Execute based on option
    case "$option_key" in
        # Base Configuration
        1.1)
            execute_module "base/system-update.sh" "--complete"
            ;;
        1.2)
            execute_module "base/shell-setup.sh" "--complete"
            ;;
        1.3)
            execute_module "base/dev-tools.sh" "--complete"
            ;;
        1.4)
            execute_module "base/user-setup.sh" "--interactive"
            ;;
        1.5)
            execute_module "base/timezone-locale.sh" "--interactive"
            ;;

        # Security Configuration
        2.1)
            execute_module "security/ssh-security.sh" "--complete"
            ;;
        2.2)
            execute_module "security/firewall.sh" "--complete"
            ;;
        2.3)
            execute_module "security/fail2ban.sh" "--complete"
            ;;
        2.4)
            execute_module "security/crowdsec.sh" "--complete"
            ;;
        2.5)
            execute_module "security/system-hardening.sh" "--complete"
            ;;
        2.6)
            execute_module "security/aide.sh" "--complete"
            ;;
        2.7)
            execute_module "security/clamav.sh" "--complete"
            ;;

        # Network Services
        3.1)
            execute_module "security/tailscale.sh" "--interactive"
            ;;
        3.2)
            execute_module "security/cloudflare.sh" "--interactive"
            ;;
        3.3)
            execute_module "security/traefik.sh" "--complete"
            ;;

        # Container Platforms
        4.1)
            execute_module "containers/docker.sh" "--complete"
            ;;
        4.2)
            execute_module "containers/podman.sh" "--complete"
            ;;
        4.3)
            execute_module "containers/coolify.sh" "--install"
            ;;

        # Monitoring & Compliance
        5.1)
            execute_module "monitoring/tools.sh" "--complete"
            ;;
        5.2)
            execute_module "monitoring/lynis.sh" "--complete"
            ;;
        5.3)
            execute_module "monitoring/logwatch.sh" "--complete"
            ;;
        5.4)
            execute_module "monitoring/compliance.sh" "--complete"
            ;;

        # Complete Setups
        6.1)
            execute_basic_setup
            ;;
        6.2)
            execute_development_setup
            ;;
        6.3)
            execute_module "scripts/zero-trust.sh" "--interactive"
            ;;
        6.4)
            execute_container_setup
            ;;

        # Utilities
        7.1)
            execute_module "scripts/documentation.sh" "--complete"
            ;;
        7.2)
            execute_module "scripts/emergency.sh" "--menu"
            ;;
        7.3)
            execute_system_backup
            ;;
        7.4)
            view_system_logs
            ;;

        *)
            print_error "Invalid option: $option_key"
            return 1
            ;;
    esac

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        mark_completed "$option_key"
        print_success "✓ ${MENU_OPTIONS[$option_key]} completed successfully"
    else
        print_error "✗ ${MENU_OPTIONS[$option_key]} failed or was cancelled"
    fi

    read -p "Press Enter to continue..."
    return $exit_code
}

# Execute module
execute_module() {
    local module_path="$1"
    local module_args="${2:-}"
    local full_path="/home/ubuntu/server-config/src/$module_path"

    if [ -f "$full_path" ]; then
        print_header "Executing: $(basename $module_path)"
        sudo bash "$full_path" $module_args
        return $?
    else
        print_error "Module not found: $module_path"
        return 1
    fi
}

# ============================================================================
# Complete Setup Functions
# ============================================================================

# Execute basic setup
execute_basic_setup() {
    print_header "Basic Server Setup"

    echo "This will install:"
    echo "  ✓ System updates"
    echo "  ✓ Essential packages"
    echo "  ✓ Basic security"
    echo "  ✓ User configuration"
    echo ""

    if confirm_action "Proceed with basic setup?"; then
        execute_module "base/system-update.sh" "--complete" && \
        execute_module "base/user-setup.sh" "--auto" && \
        execute_module "base/timezone-locale.sh" "--auto" && \
        execute_module "security/ssh-security.sh" "--harden" && \
        execute_module "security/firewall.sh" "--install"

        # Mark sub-options as completed
        mark_completed "1.1"
        mark_completed "1.4"
        mark_completed "1.5"
        mark_completed "2.1"
        mark_completed "2.2"
    fi
}

# Execute development setup
execute_development_setup() {
    print_header "Development Environment Setup"

    echo "This will install:"
    echo "  ✓ Zsh + Oh-My-Zsh"
    echo "  ✓ Development tools"
    echo "  ✓ Docker"
    echo "  ✓ Git configuration"
    echo ""

    if confirm_action "Proceed with development setup?"; then
        execute_module "base/shell-setup.sh" "--complete" && \
        execute_module "base/dev-tools.sh" "--complete" && \
        execute_module "containers/docker.sh" "--complete"

        # Mark sub-options as completed
        mark_completed "1.2"
        mark_completed "1.3"
        mark_completed "4.1"
    fi
}

# Execute container setup
execute_container_setup() {
    print_header "Container Platform Setup"

    echo "Select container platform:"
    echo "  1) Docker only"
    echo "  2) Podman only"
    echo "  3) Both Docker and Podman"
    echo ""

    read -p "Choice [1-3]: " choice

    case $choice in
        1)
            execute_module "containers/docker.sh" "--complete"
            mark_completed "4.1"
            ;;
        2)
            execute_module "containers/podman.sh" "--complete"
            mark_completed "4.2"
            ;;
        3)
            execute_module "containers/docker.sh" "--complete" && \
            execute_module "containers/podman.sh" "--complete"
            mark_completed "4.1"
            mark_completed "4.2"
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac
}

# ============================================================================
# Special Functions
# ============================================================================

# Display progress report
display_progress_report() {
    clear
    print_header "Installation Progress Report"

    if [ -f "$MENU_STATE_FILE" ]; then
        local completed=$(jq -r '.completed[]' "$MENU_STATE_FILE" 2>/dev/null)
        local in_progress=$(jq -r '.in_progress' "$MENU_STATE_FILE" 2>/dev/null)

        local total_options=$(echo "${!MENU_OPTIONS[@]}" | wc -w)
        local completed_count=$(echo "$completed" | grep -v '^$' | wc -l)
        local percentage=$((completed_count * 100 / total_options))

        echo "Overall Progress: $completed_count/$total_options ($percentage%)"
        echo ""

        # Progress bar
        local bar_length=50
        local filled=$((percentage * bar_length / 100))
        echo -n "["
        for ((i=0; i<filled; i++)); do echo -n "█"; done
        for ((i=filled; i<bar_length; i++)); do echo -n "░"; done
        echo "] $percentage%"
        echo ""

        # Category progress
        for category_num in $(echo "${!MENU_CATEGORIES[@]}" | tr ' ' '\n' | sort -n); do
            local category_name="${MENU_CATEGORIES[$category_num]}"
            local category_total=0
            local category_completed=0

            for option_key in "${!MENU_OPTIONS[@]}"; do
                if [[ $option_key == ${category_num}.* ]]; then
                    ((category_total++))
                    if echo "$completed" | grep -q "^$option_key$"; then
                        ((category_completed++))
                    fi
                fi
            done

            if [ $category_total -gt 0 ]; then
                local cat_percentage=$((category_completed * 100 / category_total))
                echo -e "${COLOR_CATEGORY}$category_name: $category_completed/$category_total ($cat_percentage%)${COLOR_RESET}"
            fi
        done

        echo ""

        # In progress
        if [ "$in_progress" != "null" ] && [ -n "$in_progress" ]; then
            echo -e "${COLOR_WARNING}In Progress:${COLOR_RESET}"
            echo "  $in_progress - ${MENU_OPTIONS[$in_progress]}"
            echo ""
        fi

        # Completed items
        if [ -n "$completed" ]; then
            echo -e "${COLOR_SUCCESS}Completed:${COLOR_RESET}"
            echo "$completed" | while read -r item; do
                [ -n "$item" ] && echo "  ✓ $item - ${MENU_OPTIONS[$item]}"
            done
        fi
    else
        print_error "No state file found"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Display system status
display_system_status() {
    clear
    print_header "System Service Status"

    local services=(
        "sshd:SSH Server"
        "ufw:Firewall"
        "fail2ban:Fail2ban"
        "crowdsec:CrowdSec"
        "docker:Docker"
        "podman:Podman"
        "nginx:Nginx"
        "apache2:Apache"
        "clamav-daemon:ClamAV"
        "aide:AIDE"
    )

    echo -e "${COLOR_INFO}Service Status:${COLOR_RESET}"
    echo ""

    for service_entry in "${services[@]}"; do
        local service="${service_entry%%:*}"
        local name="${service_entry#*:}"

        if systemctl is-enabled "$service" &>/dev/null; then
            if systemctl is-active "$service" &>/dev/null; then
                echo -e "${COLOR_SUCCESS}✓ $name: Active${COLOR_RESET}"
            else
                echo -e "${COLOR_ERROR}✗ $name: Inactive${COLOR_RESET}"
            fi
        else
            echo -e "${COLOR_WARNING}○ $name: Not installed${COLOR_RESET}"
        fi
    done

    echo ""
    echo -e "${COLOR_INFO}System Resources:${COLOR_RESET}"
    echo "  CPU Load: $(uptime | awk -F'load average:' '{print $2}')"
    echo "  Memory: $(free -h | awk '/^Mem:/{printf "%s/%s (%.0f%%)", $3, $2, $3/$2*100}')"
    echo "  Disk: $(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}')"
    echo "  Processes: $(ps aux | wc -l)"
    echo "  Uptime: $(uptime -p)"

    echo ""
    read -p "Press Enter to continue..."
}

# View history
view_history() {
    clear
    print_header "Command History"

    if [ -f "$MENU_HISTORY_FILE" ]; then
        echo "Recent activity (last 50 entries):"
        echo ""
        tail -50 "$MENU_HISTORY_FILE"
    else
        print_error "No history file found"
    fi

    echo ""
    read -p "Press Enter to continue..."
}

# Execute system backup
execute_system_backup() {
    print_header "System Configuration Backup"

    local backup_dir="/var/backups/server-config/$(date +%Y%m%d-%H%M%S)"

    echo "This will backup:"
    echo "  • System configuration files"
    echo "  • Security settings"
    echo "  • Service configurations"
    echo "  • Custom scripts"
    echo ""
    echo "Backup location: $backup_dir"
    echo ""

    if confirm_action "Proceed with backup?"; then
        sudo mkdir -p "$backup_dir"

        # Backup important directories
        local dirs_to_backup=(
            "/etc/ssh"
            "/etc/ufw"
            "/etc/fail2ban"
            "/etc/docker"
            "/etc/containers"
            "/etc/systemd/system"
            "/home/ubuntu/server-config"
        )

        for dir in "${dirs_to_backup[@]}"; do
            if [ -d "$dir" ]; then
                echo "Backing up $dir..."
                sudo cp -r "$dir" "$backup_dir/" 2>/dev/null
            fi
        done

        # Create tarball
        echo "Creating archive..."
        sudo tar -czf "$backup_dir.tar.gz" -C "$(dirname $backup_dir)" "$(basename $backup_dir)"
        sudo rm -rf "$backup_dir"

        print_success "Backup completed: $backup_dir.tar.gz"
    fi

    read -p "Press Enter to continue..."
}

# View system logs
view_system_logs() {
    clear
    print_header "System Logs Viewer"

    echo "Select log to view:"
    echo "  1) System log (syslog)"
    echo "  2) Authentication log"
    echo "  3) Kernel log"
    echo "  4) Docker logs"
    echo "  5) Fail2ban log"
    echo "  6) UFW log"
    echo "  7) All recent errors"
    echo ""

    read -p "Choice [1-7]: " choice

    case $choice in
        1)
            sudo journalctl -xe --no-pager | tail -100 | less
            ;;
        2)
            sudo tail -100 /var/log/auth.log | less
            ;;
        3)
            sudo dmesg -T | tail -100 | less
            ;;
        4)
            sudo journalctl -u docker --no-pager | tail -100 | less
            ;;
        5)
            sudo tail -100 /var/log/fail2ban.log | less
            ;;
        6)
            sudo grep -i ufw /var/log/syslog | tail -100 | less
            ;;
        7)
            sudo journalctl -p err -b --no-pager | tail -100 | less
            ;;
        *)
            print_error "Invalid choice"
            ;;
    esac

    read -p "Press Enter to continue..."
}

# ============================================================================
# Main Loop
# ============================================================================

# Main menu loop
main_menu_loop() {
    initialize_menu

    while true; do
        display_main_menu

        echo -n "Enter your choice: "
        read choice

        # Convert to uppercase for special options
        choice_upper=$(echo "$choice" | tr '[:lower:]' '[:upper:]')

        case "$choice_upper" in
            P)
                display_progress_report
                ;;
            S)
                display_system_status
                ;;
            H)
                view_history
                ;;
            R)
                if confirm_action "Reset menu state?"; then
                    reset_menu_state
                fi
                ;;
            Q)
                echo ""
                print_success "Thank you for using Ubuntu Server Configuration!"
                exit 0
                ;;
            *)
                # Check if it's a valid menu option
                if [[ -n "${MENU_OPTIONS[$choice]}" ]]; then
                    execute_option "$choice"
                else
                    print_error "Invalid option: $choice"
                    read -p "Press Enter to continue..."
                fi
                ;;
        esac
    done
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Main Menu System Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --interactive       Run interactive menu (default)
    --execute OPTION    Execute specific menu option
    --list              List all available options
    --status            Show system status
    --progress          Show progress report
    --reset             Reset menu state
    --help              Show this help message

EXAMPLES:
    # Run interactive menu
    $0
    $0 --interactive

    # Execute specific option
    $0 --execute 1.1    # Run system updates
    $0 --execute 2.1    # Harden SSH

    # View progress
    $0 --progress

    # Check status
    $0 --status

FILES:
    State File: $MENU_STATE_FILE
    History: $MENU_HISTORY_FILE
    Presets: $MENU_PRESETS_DIR

EOF
}

# List all options
list_all_options() {
    load_menu_definitions

    echo "Available Menu Options:"
    echo ""

    for category_num in $(echo "${!MENU_CATEGORIES[@]}" | tr ' ' '\n' | sort -n); do
        echo "${MENU_CATEGORIES[$category_num]}"

        for option_key in $(echo "${!MENU_OPTIONS[@]}" | tr ' ' '\n' | sort -V); do
            if [[ $option_key == ${category_num}.* ]]; then
                echo "  $option_key - ${MENU_OPTIONS[$option_key]}"
            fi
        done
        echo ""
    done
}

# Confirm action helper
confirm_action() {
    local prompt="${1:-Continue?}"
    read -p "$prompt [y/N]: " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Export functions
export -f initialize_menu display_main_menu
export -f execute_option mark_completed mark_in_progress
export -f display_progress_report display_system_status

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

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --execute)
            initialize_menu
            execute_option "${2:-}"
            ;;
        --list)
            list_all_options
            ;;
        --status)
            display_system_status
            ;;
        --progress)
            display_progress_report
            ;;
        --reset)
            reset_menu_state
            ;;
        --help)
            show_help
            ;;
        --interactive|*)
            main_menu_loop
            ;;
    esac
fi
