#!/bin/bash
# Interactive Configuration Wizards module - Guided setup with step-by-step wizards
# Provides user-friendly installation wizards with validation and rollback

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="interactive-wizards"

# Configuration
readonly WIZARD_STATE_DIR="/var/lib/server-config/wizards"
readonly WIZARD_LOG_DIR="/var/log/server-config/wizards"
readonly WIZARD_TEMP_DIR="/tmp/wizard-$$"

# Wizard state management
declare -A WIZARD_STATE
declare -A WIZARD_INPUTS
declare -A WIZARD_VALIDATIONS
declare CURRENT_WIZARD=""
declare CURRENT_STEP=0
declare TOTAL_STEPS=0

# Colors for interactive display
readonly COLOR_HEADER="\033[1;36m"
readonly COLOR_PROMPT="\033[1;33m"
readonly COLOR_INPUT="\033[1;37m"
readonly COLOR_SUCCESS="\033[0;32m"
readonly COLOR_ERROR="\033[0;31m"
readonly COLOR_INFO="\033[0;34m"
readonly COLOR_RESET="\033[0m"

# ============================================================================
# Wizard Framework
# ============================================================================

# Initialize wizard system
initialize_wizard_system() {
    # Create directories
    sudo mkdir -p "$WIZARD_STATE_DIR"
    sudo mkdir -p "$WIZARD_LOG_DIR"
    mkdir -p "$WIZARD_TEMP_DIR"

    # Initialize state
    WIZARD_STATE=()
    WIZARD_INPUTS=()
    WIZARD_VALIDATIONS=()
}

# Start wizard
start_wizard() {
    local wizard_name="$1"
    local wizard_title="$2"
    local steps="$3"

    CURRENT_WIZARD="$wizard_name"
    CURRENT_STEP=0
    TOTAL_STEPS="$steps"

    # Create wizard log
    local log_file="$WIZARD_LOG_DIR/${wizard_name}-$(date +%Y%m%d-%H%M%S).log"
    exec 3>&1 4>&2
    exec 1> >(tee -a "$log_file")
    exec 2>&1

    clear
    echo -e "${COLOR_HEADER}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                         SETUP WIZARD                               ║"
    echo "║                     $wizard_title                                  ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"
    echo ""
}

# Display wizard progress
show_wizard_progress() {
    local step_name="$1"

    ((CURRENT_STEP++))

    echo ""
    echo -e "${COLOR_INFO}Step $CURRENT_STEP of $TOTAL_STEPS: $step_name${COLOR_RESET}"

    # Progress bar
    local progress=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local bar_length=50
    local filled=$((progress * bar_length / 100))

    echo -n "["
    for ((i=0; i<filled; i++)); do echo -n "█"; done
    for ((i=filled; i<bar_length; i++)); do echo -n "░"; done
    echo "] $progress%"
    echo ""
}

# Get user input with validation
get_wizard_input() {
    local prompt="$1"
    local variable_name="$2"
    local validation_type="${3:-text}"
    local default_value="${4:-}"
    local required="${5:-true}"

    local input_valid=false
    local user_input=""

    while [ "$input_valid" = false ]; do
        echo -e "${COLOR_PROMPT}$prompt${COLOR_RESET}"

        if [ -n "$default_value" ]; then
            echo -e "${COLOR_INFO}(Default: $default_value)${COLOR_RESET}"
        fi

        echo -n "> "
        read -r user_input

        # Use default if empty and default exists
        if [ -z "$user_input" ] && [ -n "$default_value" ]; then
            user_input="$default_value"
        fi

        # Check if required
        if [ "$required" = "true" ] && [ -z "$user_input" ]; then
            echo -e "${COLOR_ERROR}This field is required${COLOR_RESET}"
            continue
        fi

        # Validate input
        if validate_wizard_input "$user_input" "$validation_type"; then
            input_valid=true
            WIZARD_INPUTS["$variable_name"]="$user_input"
            echo -e "${COLOR_SUCCESS}✓ Valid input${COLOR_RESET}"
        else
            echo -e "${COLOR_ERROR}Invalid input. Please try again.${COLOR_RESET}"
        fi
    done
}

# Validate wizard input
validate_wizard_input() {
    local input="$1"
    local validation_type="$2"

    case "$validation_type" in
        email)
            [[ "$input" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
            ;;
        ip)
            [[ "$input" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
            ;;
        port)
            [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le 65535 ]
            ;;
        domain)
            [[ "$input" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]
            ;;
        username)
            [[ "$input" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
            ;;
        password)
            [ ${#input} -ge 8 ]
            ;;
        path)
            [[ "$input" =~ ^/[a-zA-Z0-9/_.-]*$ ]]
            ;;
        yes_no)
            [[ "$input" =~ ^[yYnN]$ ]]
            ;;
        number)
            [[ "$input" =~ ^[0-9]+$ ]]
            ;;
        text|*)
            [ -n "$input" ]
            ;;
    esac
}

# Multiple choice selection
get_wizard_choice() {
    local prompt="$1"
    local variable_name="$2"
    shift 2
    local options=("$@")

    echo -e "${COLOR_PROMPT}$prompt${COLOR_RESET}"
    echo ""

    local i=1
    for option in "${options[@]}"; do
        echo "  $i) $option"
        ((i++))
    done

    echo ""
    local choice
    while true; do
        echo -n "Select [1-${#options[@]}]: "
        read -r choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            WIZARD_INPUTS["$variable_name"]="${options[$((choice-1))]}"
            echo -e "${COLOR_SUCCESS}✓ Selected: ${options[$((choice-1))]}${COLOR_RESET}"
            break
        else
            echo -e "${COLOR_ERROR}Invalid selection. Please try again.${COLOR_RESET}"
        fi
    done
}

# Confirm wizard inputs
confirm_wizard_inputs() {
    echo ""
    echo -e "${COLOR_HEADER}Review Your Configuration${COLOR_RESET}"
    echo "════════════════════════════════════════"

    for key in "${!WIZARD_INPUTS[@]}"; do
        # Format key for display
        local display_key=$(echo "$key" | tr '_' ' ' | sed 's/\b\(.\)/\u\1/g')
        echo -e "${COLOR_INFO}$display_key:${COLOR_RESET} ${WIZARD_INPUTS[$key]}"
    done

    echo ""
    echo -e "${COLOR_PROMPT}Is this configuration correct? [y/N]:${COLOR_RESET} "
    read -r confirm

    [[ "$confirm" =~ ^[yY]$ ]]
}

# Save wizard state
save_wizard_state() {
    local state_file="$WIZARD_STATE_DIR/${CURRENT_WIZARD}.state"

    {
        echo "WIZARD_NAME=$CURRENT_WIZARD"
        echo "TIMESTAMP=$(date -Iseconds)"
        echo "COMPLETED=true"
        echo ""
        echo "# Inputs"
        for key in "${!WIZARD_INPUTS[@]}"; do
            echo "INPUT_${key}=${WIZARD_INPUTS[$key]}"
        done
    } | sudo tee "$state_file" > /dev/null
}

# Load wizard state
load_wizard_state() {
    local wizard_name="$1"
    local state_file="$WIZARD_STATE_DIR/${wizard_name}.state"

    if [ -f "$state_file" ]; then
        source "$state_file"
        return 0
    fi

    return 1
}

# ============================================================================
# Quick Setup Wizard
# ============================================================================

# Run quick setup wizard
run_quick_setup_wizard() {
    start_wizard "quick_setup" "Quick Server Setup" 5

    # Step 1: Server purpose
    show_wizard_progress "Server Purpose"
    get_wizard_choice "What is the primary purpose of this server?" "server_purpose" \
        "Web Server" \
        "Database Server" \
        "Application Server" \
        "Development Server" \
        "General Purpose"

    # Step 2: Security level
    show_wizard_progress "Security Level"
    get_wizard_choice "Select security level:" "security_level" \
        "Basic (Firewall + SSH hardening)" \
        "Standard (Basic + Fail2ban)" \
        "Enhanced (Standard + CrowdSec + ClamAV)" \
        "Maximum (Zero Trust Architecture)"

    # Step 3: Container platform
    show_wizard_progress "Container Platform"
    get_wizard_choice "Select container platform:" "container_platform" \
        "Docker" \
        "Podman" \
        "Both Docker and Podman" \
        "None"

    # Step 4: Monitoring
    show_wizard_progress "Monitoring Setup"
    get_wizard_choice "Configure monitoring?" "monitoring" \
        "Yes - Full monitoring suite" \
        "Yes - Basic monitoring only" \
        "No - Skip monitoring"

    # Step 5: Confirmation
    show_wizard_progress "Confirmation"

    if confirm_wizard_inputs; then
        echo ""
        echo -e "${COLOR_INFO}Applying configuration...${COLOR_RESET}"

        # Execute based on selections
        execute_quick_setup

        save_wizard_state
        echo -e "${COLOR_SUCCESS}✓ Quick setup completed successfully!${COLOR_RESET}"
    else
        echo -e "${COLOR_ERROR}Setup cancelled${COLOR_RESET}"
        return 1
    fi
}

# Execute quick setup based on wizard inputs
execute_quick_setup() {
    local script_dir="/home/ubuntu/server-config/src"

    # Basic system setup
    sudo bash "$script_dir/base/system-update.sh" --complete

    # Security setup based on level
    case "${WIZARD_INPUTS[security_level]}" in
        "Basic"*)
            sudo bash "$script_dir/security/ssh-security.sh" --harden
            sudo bash "$script_dir/security/firewall.sh" --install
            ;;
        "Standard"*)
            sudo bash "$script_dir/security/ssh-security.sh" --harden
            sudo bash "$script_dir/security/firewall.sh" --install
            sudo bash "$script_dir/security/fail2ban.sh" --install
            ;;
        "Enhanced"*)
            sudo bash "$script_dir/security/ssh-security.sh" --harden
            sudo bash "$script_dir/security/firewall.sh" --install
            sudo bash "$script_dir/security/fail2ban.sh" --install
            sudo bash "$script_dir/security/crowdsec.sh" --install
            sudo bash "$script_dir/security/clamav.sh" --install
            ;;
        "Maximum"*)
            sudo bash "$script_dir/scripts/zero-trust.sh" --auto
            ;;
    esac

    # Container platform
    case "${WIZARD_INPUTS[container_platform]}" in
        "Docker")
            sudo bash "$script_dir/containers/docker.sh" --complete
            ;;
        "Podman")
            sudo bash "$script_dir/containers/podman.sh" --complete
            ;;
        "Both"*)
            sudo bash "$script_dir/containers/docker.sh" --complete
            sudo bash "$script_dir/containers/podman.sh" --complete
            ;;
    esac

    # Monitoring
    case "${WIZARD_INPUTS[monitoring]}" in
        "Yes - Full"*)
            sudo bash "$script_dir/monitoring/tools.sh" --complete
            sudo bash "$script_dir/monitoring/lynis.sh" --install
            sudo bash "$script_dir/monitoring/logwatch.sh" --install
            ;;
        "Yes - Basic"*)
            sudo bash "$script_dir/monitoring/tools.sh" --basic
            ;;
    esac
}

# ============================================================================
# Security Hardening Wizard
# ============================================================================

# Run security hardening wizard
run_security_wizard() {
    start_wizard "security_hardening" "Security Hardening Wizard" 8

    # Step 1: SSH Configuration
    show_wizard_progress "SSH Configuration"
    get_wizard_input "SSH Port (22):" "ssh_port" "port" "22"
    get_wizard_choice "Allow root login?" "ssh_root_login" "No (Recommended)" "Yes"
    get_wizard_choice "Password authentication?" "ssh_password_auth" "No (Key only)" "Yes"

    # Step 2: Firewall Rules
    show_wizard_progress "Firewall Configuration"
    get_wizard_input "Additional ports to open (comma-separated):" "firewall_ports" "text" "" "false"
    get_wizard_choice "Default policy:" "firewall_default" "Deny all (Recommended)" "Allow all"

    # Step 3: Intrusion Prevention
    show_wizard_progress "Intrusion Prevention"
    get_wizard_choice "Install Fail2ban?" "install_fail2ban" "Yes" "No"
    get_wizard_choice "Install CrowdSec?" "install_crowdsec" "Yes" "No"

    # Step 4: System Hardening
    show_wizard_progress "System Hardening"
    get_wizard_choice "Apply kernel hardening?" "kernel_hardening" "Yes" "No"
    get_wizard_choice "Configure AppArmor?" "apparmor" "Yes" "No"
    get_wizard_choice "Enable audit system?" "audit_system" "Yes" "No"

    # Step 5: File Integrity
    show_wizard_progress "File Integrity Monitoring"
    get_wizard_choice "Install AIDE?" "install_aide" "Yes" "No"
    get_wizard_choice "Schedule daily checks?" "aide_daily" "Yes" "No"

    # Step 6: Malware Protection
    show_wizard_progress "Malware Protection"
    get_wizard_choice "Install ClamAV?" "install_clamav" "Yes" "No"
    get_wizard_choice "Enable real-time scanning?" "clamav_realtime" "Yes" "No"

    # Step 7: Network Security
    show_wizard_progress "Network Security"
    get_wizard_choice "Setup VPN (Tailscale)?" "setup_vpn" "Yes" "No"
    get_wizard_choice "Configure reverse proxy?" "setup_proxy" "Yes" "No"

    # Step 8: Confirmation
    show_wizard_progress "Confirmation"

    if confirm_wizard_inputs; then
        echo ""
        echo -e "${COLOR_INFO}Applying security configuration...${COLOR_RESET}"
        execute_security_hardening
        save_wizard_state
        echo -e "${COLOR_SUCCESS}✓ Security hardening completed!${COLOR_RESET}"
    else
        echo -e "${COLOR_ERROR}Setup cancelled${COLOR_RESET}"
        return 1
    fi
}

# Execute security hardening
execute_security_hardening() {
    local script_dir="/home/ubuntu/server-config/src"

    # SSH hardening
    if [ "${WIZARD_INPUTS[ssh_port]}" != "22" ]; then
        sudo sed -i "s/^#*Port .*/Port ${WIZARD_INPUTS[ssh_port]}/" /etc/ssh/sshd_config
    fi

    # Apply selections
    [ "${WIZARD_INPUTS[install_fail2ban]}" = "Yes" ] && \
        sudo bash "$script_dir/security/fail2ban.sh" --install

    [ "${WIZARD_INPUTS[install_crowdsec]}" = "Yes" ] && \
        sudo bash "$script_dir/security/crowdsec.sh" --install

    [ "${WIZARD_INPUTS[kernel_hardening]}" = "Yes" ] && \
        sudo bash "$script_dir/security/system-hardening.sh" --kernel

    [ "${WIZARD_INPUTS[install_aide]}" = "Yes" ] && \
        sudo bash "$script_dir/security/aide.sh" --complete

    [ "${WIZARD_INPUTS[install_clamav]}" = "Yes" ] && \
        sudo bash "$script_dir/security/clamav.sh" --complete

    [ "${WIZARD_INPUTS[setup_vpn]}" = "Yes" ] && \
        sudo bash "$script_dir/security/tailscale.sh" --interactive
}

# ============================================================================
# Development Environment Wizard
# ============================================================================

# Run development environment wizard
run_development_wizard() {
    start_wizard "development_env" "Development Environment Setup" 6

    # Step 1: Shell configuration
    show_wizard_progress "Shell Configuration"
    get_wizard_choice "Install Zsh + Oh-My-Zsh?" "install_zsh" "Yes" "No"
    get_wizard_choice "Theme preference:" "zsh_theme" "Powerlevel10k" "Agnoster" "Robbyrussell" "Default"

    # Step 2: Development tools
    show_wizard_progress "Development Tools"
    get_wizard_choice "Install Node.js (via NVM)?" "install_nodejs" "Yes" "No"
    get_wizard_input "Node.js version (lts):" "node_version" "text" "lts" "false"
    get_wizard_choice "Install Python tools?" "install_python" "Yes" "No"
    get_wizard_choice "Install Go?" "install_go" "Yes" "No"

    # Step 3: Container tools
    show_wizard_progress "Container Tools"
    get_wizard_choice "Container platform:" "container_platform" \
        "Docker" \
        "Podman" \
        "Both" \
        "None"
    get_wizard_choice "Install docker-compose?" "install_compose" "Yes" "No"

    # Step 4: Version control
    show_wizard_progress "Version Control"
    get_wizard_input "Git user name:" "git_name" "text" "" "false"
    get_wizard_input "Git user email:" "git_email" "email" "" "false"

    # Step 5: IDE/Editor
    show_wizard_progress "IDE and Editors"
    get_wizard_choice "Configure Vim?" "configure_vim" "Yes" "No"
    get_wizard_choice "Install VS Code Server?" "install_vscode" "Yes" "No"

    # Step 6: Confirmation
    show_wizard_progress "Confirmation"

    if confirm_wizard_inputs; then
        echo ""
        echo -e "${COLOR_INFO}Setting up development environment...${COLOR_RESET}"
        execute_development_setup
        save_wizard_state
        echo -e "${COLOR_SUCCESS}✓ Development environment ready!${COLOR_RESET}"
    else
        echo -e "${COLOR_ERROR}Setup cancelled${COLOR_RESET}"
        return 1
    fi
}

# Execute development setup
execute_development_setup() {
    local script_dir="/home/ubuntu/server-config/src"

    # Shell setup
    [ "${WIZARD_INPUTS[install_zsh]}" = "Yes" ] && \
        sudo bash "$script_dir/base/shell-setup.sh" --complete

    # Development tools
    [ "${WIZARD_INPUTS[install_nodejs]}" = "Yes" ] && \
        sudo bash "$script_dir/base/dev-tools.sh" --nvm

    # Container platform
    case "${WIZARD_INPUTS[container_platform]}" in
        "Docker")
            sudo bash "$script_dir/containers/docker.sh" --complete
            ;;
        "Podman")
            sudo bash "$script_dir/containers/podman.sh" --complete
            ;;
        "Both")
            sudo bash "$script_dir/containers/docker.sh" --complete
            sudo bash "$script_dir/containers/podman.sh" --complete
            ;;
    esac

    # Git configuration
    if [ -n "${WIZARD_INPUTS[git_name]}" ]; then
        git config --global user.name "${WIZARD_INPUTS[git_name]}"
    fi
    if [ -n "${WIZARD_INPUTS[git_email]}" ]; then
        git config --global user.email "${WIZARD_INPUTS[git_email]}"
    fi
}

# ============================================================================
# Network Configuration Wizard
# ============================================================================

# Run network configuration wizard
run_network_wizard() {
    start_wizard "network_config" "Network Configuration Wizard" 6

    # Step 1: Hostname
    show_wizard_progress "System Identity"
    get_wizard_input "Hostname:" "hostname" "text" "$(hostname)" "true"
    get_wizard_input "Domain name:" "domain" "domain" "" "false"

    # Step 2: Network interfaces
    show_wizard_progress "Network Interfaces"
    get_wizard_choice "Configure static IP?" "static_ip" "No" "Yes"

    if [ "${WIZARD_INPUTS[static_ip]}" = "Yes" ]; then
        get_wizard_input "IP Address:" "ip_address" "ip"
        get_wizard_input "Netmask:" "netmask" "ip" "255.255.255.0"
        get_wizard_input "Gateway:" "gateway" "ip"
        get_wizard_input "DNS Servers (comma-separated):" "dns_servers" "text"
    fi

    # Step 3: Firewall
    show_wizard_progress "Firewall Configuration"
    get_wizard_input "SSH Port:" "ssh_port" "port" "22"
    get_wizard_input "HTTP Port (0 to skip):" "http_port" "port" "80"
    get_wizard_input "HTTPS Port (0 to skip):" "https_port" "port" "443"
    get_wizard_input "Custom ports (comma-separated):" "custom_ports" "text" "" "false"

    # Step 4: VPN
    show_wizard_progress "VPN Configuration"
    get_wizard_choice "Setup Tailscale VPN?" "setup_tailscale" "Yes" "No"
    if [ "${WIZARD_INPUTS[setup_tailscale]}" = "Yes" ]; then
        get_wizard_input "Tailscale auth key:" "tailscale_key" "text" "" "false"
    fi

    # Step 5: Reverse Proxy
    show_wizard_progress "Reverse Proxy"
    get_wizard_choice "Setup reverse proxy?" "setup_proxy" "No" "Traefik" "Nginx" "Caddy"

    # Step 6: Confirmation
    show_wizard_progress "Confirmation"

    if confirm_wizard_inputs; then
        echo ""
        echo -e "${COLOR_INFO}Applying network configuration...${COLOR_RESET}"
        execute_network_setup
        save_wizard_state
        echo -e "${COLOR_SUCCESS}✓ Network configuration completed!${COLOR_RESET}"
    else
        echo -e "${COLOR_ERROR}Setup cancelled${COLOR_RESET}"
        return 1
    fi
}

# Execute network setup
execute_network_setup() {
    local script_dir="/home/ubuntu/server-config/src"

    # Set hostname
    if [ -n "${WIZARD_INPUTS[hostname]}" ]; then
        sudo hostnamectl set-hostname "${WIZARD_INPUTS[hostname]}"
    fi

    # Configure firewall
    sudo bash "$script_dir/security/firewall.sh" --install

    # Open ports
    [ "${WIZARD_INPUTS[http_port]}" != "0" ] && \
        sudo ufw allow "${WIZARD_INPUTS[http_port]}/tcp"

    [ "${WIZARD_INPUTS[https_port]}" != "0" ] && \
        sudo ufw allow "${WIZARD_INPUTS[https_port]}/tcp"

    # Setup VPN
    [ "${WIZARD_INPUTS[setup_tailscale]}" = "Yes" ] && \
        sudo bash "$script_dir/security/tailscale.sh" --install

    # Setup proxy
    case "${WIZARD_INPUTS[setup_proxy]}" in
        "Traefik")
            sudo bash "$script_dir/security/traefik.sh" --install
            ;;
    esac
}

# ============================================================================
# Container Platform Wizard
# ============================================================================

# Run container platform wizard
run_container_wizard() {
    start_wizard "container_platform" "Container Platform Setup" 5

    # Step 1: Platform selection
    show_wizard_progress "Platform Selection"
    get_wizard_choice "Primary container platform:" "primary_platform" \
        "Docker (Most compatible)" \
        "Podman (Rootless, more secure)" \
        "Both (Maximum flexibility)"

    # Step 2: Docker configuration
    if [[ "${WIZARD_INPUTS[primary_platform]}" == *"Docker"* ]] || \
       [[ "${WIZARD_INPUTS[primary_platform]}" == *"Both"* ]]; then
        show_wizard_progress "Docker Configuration"
        get_wizard_choice "Docker storage driver:" "docker_storage" "overlay2" "devicemapper" "btrfs"
        get_wizard_choice "Enable Docker Swarm?" "docker_swarm" "No" "Yes"
        get_wizard_choice "Install Docker Compose?" "docker_compose" "Yes" "No"
    fi

    # Step 3: Podman configuration
    if [[ "${WIZARD_INPUTS[primary_platform]}" == *"Podman"* ]] || \
       [[ "${WIZARD_INPUTS[primary_platform]}" == *"Both"* ]]; then
        show_wizard_progress "Podman Configuration"
        get_wizard_choice "Enable rootless mode?" "podman_rootless" "Yes (Recommended)" "No"
        get_wizard_choice "Docker compatibility mode?" "podman_docker_compat" "Yes" "No"
        get_wizard_choice "Install Podman Compose?" "podman_compose" "Yes" "No"
    fi

    # Step 4: Orchestration
    show_wizard_progress "Container Orchestration"
    get_wizard_choice "Install orchestration platform?" "orchestration" \
        "None" \
        "Coolify (Simple PaaS)" \
        "Portainer (Web UI)" \
        "K3s (Lightweight Kubernetes)"

    # Step 5: Confirmation
    show_wizard_progress "Confirmation"

    if confirm_wizard_inputs; then
        echo ""
        echo -e "${COLOR_INFO}Setting up container platform...${COLOR_RESET}"
        execute_container_setup
        save_wizard_state
        echo -e "${COLOR_SUCCESS}✓ Container platform ready!${COLOR_RESET}"
    else
        echo -e "${COLOR_ERROR}Setup cancelled${COLOR_RESET}"
        return 1
    fi
}

# Execute container setup
execute_container_setup() {
    local script_dir="/home/ubuntu/server-config/src"

    # Install platforms
    case "${WIZARD_INPUTS[primary_platform]}" in
        *"Docker"*)
            sudo bash "$script_dir/containers/docker.sh" --complete
            ;;
        *"Podman"*)
            sudo bash "$script_dir/containers/podman.sh" --complete
            ;;
        *"Both"*)
            sudo bash "$script_dir/containers/docker.sh" --complete
            sudo bash "$script_dir/containers/podman.sh" --complete
            ;;
    esac

    # Install orchestration
    case "${WIZARD_INPUTS[orchestration]}" in
        *"Coolify"*)
            sudo bash "$script_dir/containers/coolify.sh" --install
            ;;
    esac
}

# ============================================================================
# Production Server Wizard
# ============================================================================

# Run production server wizard
run_production_wizard() {
    start_wizard "production_server" "Production Server Setup" 7

    # Step 1: Server role
    show_wizard_progress "Server Role"
    get_wizard_choice "Primary server role:" "server_role" \
        "Web Server" \
        "API Server" \
        "Database Server" \
        "Load Balancer" \
        "Application Server"

    # Step 2: High availability
    show_wizard_progress "High Availability"
    get_wizard_choice "Configure for high availability?" "high_availability" "Yes" "No"
    get_wizard_choice "Enable automatic failover?" "auto_failover" "Yes" "No"
    get_wizard_choice "Setup backup strategy?" "backup_strategy" "Yes" "No"

    # Step 3: Performance
    show_wizard_progress "Performance Optimization"
    get_wizard_choice "Optimize kernel parameters?" "kernel_optimize" "Yes" "No"
    get_wizard_choice "Configure caching?" "caching" "Yes" "No"
    get_wizard_choice "Setup CDN integration?" "cdn_integration" "No" "Cloudflare" "AWS CloudFront"

    # Step 4: Security
    show_wizard_progress "Security Configuration"
    get_wizard_choice "Security level:" "security_level" \
        "Standard" \
        "Enhanced" \
        "Maximum (Zero Trust)"
    get_wizard_choice "Enable DDoS protection?" "ddos_protection" "Yes" "No"
    get_wizard_choice "Configure WAF?" "waf" "No" "ModSecurity" "Cloudflare"

    # Step 5: Monitoring
    show_wizard_progress "Monitoring and Alerting"
    get_wizard_choice "Monitoring level:" "monitoring_level" \
        "Basic (System metrics)" \
        "Standard (+ Application metrics)" \
        "Comprehensive (+ APM)"
    get_wizard_input "Alert email:" "alert_email" "email" "" "false"

    # Step 6: Compliance
    show_wizard_progress "Compliance Requirements"
    get_wizard_choice "Compliance framework:" "compliance" \
        "None" \
        "PCI-DSS" \
        "HIPAA" \
        "SOC 2" \
        "GDPR"

    # Step 7: Confirmation
    show_wizard_progress "Confirmation"

    if confirm_wizard_inputs; then
        echo ""
        echo -e "${COLOR_INFO}Configuring production server...${COLOR_RESET}"
        execute_production_setup
        save_wizard_state
        echo -e "${COLOR_SUCCESS}✓ Production server configured!${COLOR_RESET}"
    else
        echo -e "${COLOR_ERROR}Setup cancelled${COLOR_RESET}"
        return 1
    fi
}

# Execute production setup
execute_production_setup() {
    local script_dir="/home/ubuntu/server-config/src"

    # Apply security based on level
    case "${WIZARD_INPUTS[security_level]}" in
        "Maximum"*)
            sudo bash "$script_dir/scripts/zero-trust.sh" --auto
            ;;
        "Enhanced")
            sudo bash "$script_dir/security/system-hardening.sh" --complete
            sudo bash "$script_dir/security/fail2ban.sh" --install
            sudo bash "$script_dir/security/crowdsec.sh" --install
            ;;
        *)
            sudo bash "$script_dir/security/firewall.sh" --install
            sudo bash "$script_dir/security/ssh-security.sh" --harden
            ;;
    esac

    # Setup monitoring
    case "${WIZARD_INPUTS[monitoring_level]}" in
        "Comprehensive"*)
            sudo bash "$script_dir/monitoring/tools.sh" --complete
            sudo bash "$script_dir/monitoring/compliance.sh" --setup
            ;;
        "Standard"*)
            sudo bash "$script_dir/monitoring/tools.sh" --complete
            ;;
        *)
            sudo bash "$script_dir/monitoring/tools.sh" --basic
            ;;
    esac

    # Configure compliance if needed
    if [ "${WIZARD_INPUTS[compliance]}" != "None" ]; then
        sudo bash "$script_dir/monitoring/compliance.sh" --check "${WIZARD_INPUTS[compliance],,}"
    fi
}

# ============================================================================
# Wizard Menu
# ============================================================================

# Display wizard menu
display_wizard_menu() {
    clear
    echo -e "${COLOR_HEADER}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                  Interactive Configuration Wizards                 ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"
    echo ""
    echo "Select a wizard to run:"
    echo ""
    echo "  1) Quick Setup          - Basic server configuration"
    echo "  2) Security Hardening   - Comprehensive security setup"
    echo "  3) Development Setup    - Development environment"
    echo "  4) Network Setup        - Network and connectivity"
    echo "  5) Container Platform   - Docker/Podman setup"
    echo "  6) Production Server    - Production-ready configuration"
    echo ""
    echo "  R) Recent Wizards       - View recently run wizards"
    echo "  S) Saved Configurations - Load saved configuration"
    echo "  Q) Quit                 - Exit wizard menu"
    echo ""
}

# Run wizard menu
run_wizard_menu() {
    initialize_wizard_system

    while true; do
        display_wizard_menu
        echo -n "Select wizard [1-6,R,S,Q]: "
        read -r choice

        case "${choice^^}" in
            1)
                run_quick_setup_wizard
                ;;
            2)
                run_security_wizard
                ;;
            3)
                run_development_wizard
                ;;
            4)
                run_network_wizard
                ;;
            5)
                run_container_wizard
                ;;
            6)
                run_production_wizard
                ;;
            R)
                view_recent_wizards
                ;;
            S)
                load_saved_configuration
                ;;
            Q)
                echo -e "${COLOR_SUCCESS}Exiting wizard menu${COLOR_RESET}"
                break
                ;;
            *)
                echo -e "${COLOR_ERROR}Invalid selection${COLOR_RESET}"
                ;;
        esac

        if [[ ! "${choice^^}" =~ ^[QRS]$ ]]; then
            echo ""
            echo "Press Enter to continue..."
            read -r
        fi
    done
}

# View recent wizards
view_recent_wizards() {
    clear
    echo -e "${COLOR_HEADER}Recent Wizard Runs${COLOR_RESET}"
    echo ""

    if [ -d "$WIZARD_LOG_DIR" ]; then
        ls -lt "$WIZARD_LOG_DIR"/*.log 2>/dev/null | head -10 | while read -r line; do
            echo "$line"
        done
    else
        echo "No recent wizard runs found"
    fi

    echo ""
    echo "Press Enter to continue..."
    read -r
}

# Load saved configuration
load_saved_configuration() {
    clear
    echo -e "${COLOR_HEADER}Saved Configurations${COLOR_RESET}"
    echo ""

    if [ -d "$WIZARD_STATE_DIR" ]; then
        local configs=($(ls "$WIZARD_STATE_DIR"/*.state 2>/dev/null))

        if [ ${#configs[@]} -eq 0 ]; then
            echo "No saved configurations found"
        else
            echo "Available configurations:"
            local i=1
            for config in "${configs[@]}"; do
                local name=$(basename "$config" .state)
                echo "  $i) $name"
                ((i++))
            done

            echo ""
            echo -n "Select configuration to load [1-${#configs[@]}]: "
            read -r choice

            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#configs[@]}" ]; then
                local selected="${configs[$((choice-1))]}"
                echo ""
                echo "Configuration details:"
                cat "$selected"
            fi
        fi
    fi

    echo ""
    echo "Press Enter to continue..."
    read -r
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Interactive Configuration Wizards Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --menu              Run interactive wizard menu (default)
    --quick             Run quick setup wizard
    --security          Run security hardening wizard
    --development       Run development environment wizard
    --network           Run network configuration wizard
    --container         Run container platform wizard
    --production        Run production server wizard
    --list              List available wizards
    --help              Show this help message

WIZARDS:
    Quick Setup         Basic server configuration
    Security Hardening  Comprehensive security setup
    Development Setup   Development environment
    Network Setup       Network and connectivity
    Container Platform  Docker/Podman setup
    Production Server   Production-ready configuration

EXAMPLES:
    # Run wizard menu
    $0 --menu

    # Run specific wizard
    $0 --quick
    $0 --security

    # List available wizards
    $0 --list

FILES:
    State Directory: $WIZARD_STATE_DIR
    Log Directory: $WIZARD_LOG_DIR

EOF
}

# List available wizards
list_wizards() {
    echo "Available Configuration Wizards:"
    echo ""
    echo "1. Quick Setup Wizard"
    echo "   - Basic server configuration"
    echo "   - Select security level"
    echo "   - Choose container platform"
    echo ""
    echo "2. Security Hardening Wizard"
    echo "   - SSH configuration"
    echo "   - Firewall setup"
    echo "   - Intrusion prevention"
    echo "   - File integrity monitoring"
    echo ""
    echo "3. Development Environment Wizard"
    echo "   - Shell configuration"
    echo "   - Development tools"
    echo "   - Container tools"
    echo "   - IDE setup"
    echo ""
    echo "4. Network Configuration Wizard"
    echo "   - Hostname and domain"
    echo "   - Network interfaces"
    echo "   - Firewall rules"
    echo "   - VPN setup"
    echo ""
    echo "5. Container Platform Wizard"
    echo "   - Docker/Podman selection"
    echo "   - Storage configuration"
    echo "   - Orchestration setup"
    echo ""
    echo "6. Production Server Wizard"
    echo "   - Server role configuration"
    echo "   - High availability"
    echo "   - Performance optimization"
    echo "   - Compliance setup"
}

# Export functions
export -f initialize_wizard_system start_wizard
export -f get_wizard_input get_wizard_choice
export -f run_quick_setup_wizard run_security_wizard
export -f run_development_wizard run_network_wizard
export -f run_container_wizard run_production_wizard

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
source "${SCRIPT_DIR}/../lib/validation.sh" 2>/dev/null || true

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --quick)
            initialize_wizard_system
            run_quick_setup_wizard
            ;;
        --security)
            initialize_wizard_system
            run_security_wizard
            ;;
        --development)
            initialize_wizard_system
            run_development_wizard
            ;;
        --network)
            initialize_wizard_system
            run_network_wizard
            ;;
        --container)
            initialize_wizard_system
            run_container_wizard
            ;;
        --production)
            initialize_wizard_system
            run_production_wizard
            ;;
        --list)
            list_wizards
            ;;
        --help)
            show_help
            ;;
        --menu|*)
            run_wizard_menu
            ;;
    esac
fi
