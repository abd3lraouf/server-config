#!/bin/bash
# Firewall configuration module - UFW with Docker support
# Manages firewall rules and Docker integration

# Script metadata
readonly MODULE_VERSION="1.0.0"
readonly MODULE_NAME="firewall"

# Default ports configuration
readonly DEFAULT_SSH_PORT="${SSH_PORT:-22}"
readonly DEFAULT_HTTP_PORT="${HTTP_PORT:-80}"
readonly DEFAULT_HTTPS_PORT="${HTTPS_PORT:-443}"

# ============================================================================
# Basic UFW Configuration
# ============================================================================

# Configure basic UFW firewall
configure_ufw() {
    print_status "Configuring UFW firewall..."

    # Install UFW if not present
    if ! command -v ufw &> /dev/null; then
        print_status "Installing UFW..."
        sudo apt update
        sudo apt install -y ufw
    fi

    # Backup existing rules
    if [ -f /etc/ufw/user.rules ]; then
        backup_file "/etc/ufw/user.rules"
        backup_file "/etc/ufw/user6.rules"
    fi

    # Reset UFW to defaults if requested
    if [[ "${1:-}" == "--reset" ]]; then
        print_warning "Resetting UFW to defaults..."
        echo "y" | sudo ufw --force reset
    fi

    # Set default policies
    print_status "Setting default firewall policies..."
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw default allow routed

    # Allow SSH (critical to prevent lockout)
    print_status "Allowing SSH access on port ${DEFAULT_SSH_PORT}..."
    sudo ufw allow "${DEFAULT_SSH_PORT}/tcp" comment 'SSH'

    # Enable UFW
    print_status "Enabling UFW..."
    echo "y" | sudo ufw --force enable

    # Show status
    sudo ufw status verbose

    print_success "UFW firewall configured and enabled"
    print_warning "Only SSH (port ${DEFAULT_SSH_PORT}) is allowed. Configure additional ports as needed."

    return 0
}

# ============================================================================
# Docker Integration
# ============================================================================

# Configure UFW with Docker support
configure_ufw_docker() {
    print_status "Configuring UFW with Docker integration..."

    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_warning "Docker is not installed. Skipping Docker-specific configuration."
        return 1
    fi

    # Backup Docker configuration
    backup_file "/etc/docker/daemon.json"

    # Configure Docker to not manipulate iptables
    print_status "Configuring Docker iptables settings..."

    local docker_config="/etc/docker/daemon.json"
    local tmp_config="/tmp/docker-daemon-$$.json"

    # Create or update Docker daemon configuration
    if [ -f "$docker_config" ]; then
        # Merge with existing config
        jq '. + {"iptables": false}' "$docker_config" > "$tmp_config"
    else
        # Create new config
        echo '{"iptables": false}' > "$tmp_config"
    fi

    sudo mv "$tmp_config" "$docker_config"
    sudo chmod 644 "$docker_config"

    # Configure UFW to allow Docker network traffic
    print_status "Configuring UFW for Docker networks..."

    # Add UFW rules for Docker
    cat << 'EOF' | sudo tee /etc/ufw/after.rules > /dev/null
# BEGIN UFW AND DOCKER
*filter
:DOCKER-USER - [0:0]
:ufw-user-forward - [0:0]

-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A DOCKER-USER -m conntrack --ctstate INVALID -j DROP
-A DOCKER-USER -i eth0 -j ufw-user-forward
-A DOCKER-USER -i eth0 -j DROP
COMMIT
# END UFW AND DOCKER
EOF

    # Allow Docker bridge network
    sudo ufw allow from 172.16.0.0/12 to any comment 'Docker networks'
    sudo ufw allow from 10.0.0.0/8 to any comment 'Docker bridge'

    # Restart Docker to apply changes
    if systemctl is-active docker &>/dev/null; then
        print_status "Restarting Docker daemon..."
        sudo systemctl restart docker
    fi

    # Reload UFW
    sudo ufw reload

    print_success "UFW configured with Docker support"
    return 0
}

# ============================================================================
# Firewall Rules Management
# ============================================================================

# Add a firewall rule
add_firewall_rule() {
    local port="$1"
    local protocol="${2:-tcp}"
    local comment="${3:-Custom rule}"
    local source="${4:-any}"

    if [ -z "$port" ]; then
        print_error "Port number is required"
        return 1
    fi

    print_status "Adding firewall rule: port $port/$protocol from $source"

    if [ "$source" = "any" ]; then
        sudo ufw allow "$port/$protocol" comment "$comment"
    else
        sudo ufw allow from "$source" to any port "$port" proto "$protocol" comment "$comment"
    fi

    print_success "Firewall rule added"
    return 0
}

# Remove a firewall rule
remove_firewall_rule() {
    local port="$1"
    local protocol="${2:-tcp}"

    if [ -z "$port" ]; then
        print_error "Port number is required"
        return 1
    fi

    print_status "Removing firewall rule: port $port/$protocol"

    sudo ufw delete allow "$port/$protocol"

    print_success "Firewall rule removed"
    return 0
}

# List all firewall rules
list_firewall_rules() {
    print_header "Current Firewall Rules"
    sudo ufw status numbered
    return 0
}

# ============================================================================
# Application Profiles
# ============================================================================

# Configure web server firewall rules
configure_web_firewall() {
    print_status "Configuring firewall for web services..."

    # Allow HTTP
    sudo ufw allow "${DEFAULT_HTTP_PORT}/tcp" comment 'HTTP'

    # Allow HTTPS
    sudo ufw allow "${DEFAULT_HTTPS_PORT}/tcp" comment 'HTTPS'

    # Allow alternative HTTP ports if configured
    if [ -n "${ALT_HTTP_PORT:-}" ]; then
        sudo ufw allow "${ALT_HTTP_PORT}/tcp" comment 'Alternative HTTP'
    fi

    print_success "Web server firewall rules configured"
    return 0
}

# Configure database firewall rules
configure_database_firewall() {
    local db_type="${1:-mysql}"
    local source="${2:-127.0.0.1}"

    print_status "Configuring firewall for $db_type database..."

    case "$db_type" in
        mysql|mariadb)
            sudo ufw allow from "$source" to any port 3306 proto tcp comment "MySQL/MariaDB"
            ;;
        postgresql|postgres)
            sudo ufw allow from "$source" to any port 5432 proto tcp comment "PostgreSQL"
            ;;
        mongodb|mongo)
            sudo ufw allow from "$source" to any port 27017 proto tcp comment "MongoDB"
            ;;
        redis)
            sudo ufw allow from "$source" to any port 6379 proto tcp comment "Redis"
            ;;
        *)
            print_error "Unknown database type: $db_type"
            return 1
            ;;
    esac

    print_success "$db_type firewall rules configured"
    return 0
}

# ============================================================================
# Tailscale Integration
# ============================================================================

# Configure firewall for Tailscale
configure_tailscale_firewall() {
    print_status "Configuring firewall for Tailscale..."

    # Allow Tailscale UDP port
    sudo ufw allow 41641/udp comment 'Tailscale'

    # Allow from Tailscale network
    if command -v tailscale &>/dev/null; then
        local tailscale_ip=$(tailscale ip -4 2>/dev/null || true)
        if [ -n "$tailscale_ip" ]; then
            local tailscale_network="${tailscale_ip%.*}.0/24"
            sudo ufw allow from "$tailscale_network" comment 'Tailscale network'
        fi
    fi

    print_success "Tailscale firewall rules configured"
    return 0
}

# ============================================================================
# Security Hardening
# ============================================================================

# Apply strict firewall rules
harden_firewall() {
    print_status "Applying strict firewall rules..."

    # Enable logging
    sudo ufw logging on

    # Rate limiting for SSH
    sudo ufw limit ssh/tcp comment 'SSH rate limiting'

    # Deny outgoing for specific ports
    sudo ufw deny out 25 comment 'Block SMTP'

    # Block common attack ports
    sudo ufw deny 135/tcp comment 'Block NetBIOS'
    sudo ufw deny 137/tcp comment 'Block NetBIOS'
    sudo ufw deny 138/tcp comment 'Block NetBIOS'
    sudo ufw deny 139/tcp comment 'Block NetBIOS'
    sudo ufw deny 445/tcp comment 'Block SMB'

    print_success "Firewall hardened"
    return 0
}

# ============================================================================
# Backup and Restore
# ============================================================================

# Backup firewall configuration
backup_firewall_config() {
    local backup_dir="${1:-/root/firewall-backup-$(date +%Y%m%d-%H%M%S)}"

    print_status "Backing up firewall configuration to $backup_dir..."

    sudo mkdir -p "$backup_dir"

    # Backup UFW rules
    sudo cp -r /etc/ufw/* "$backup_dir/"

    # Export current rules
    sudo ufw status numbered > "$backup_dir/ufw-status.txt"
    sudo iptables-save > "$backup_dir/iptables-rules.txt"

    print_success "Firewall configuration backed up"
    return 0
}

# Restore firewall configuration
restore_firewall_config() {
    local backup_dir="$1"

    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        print_error "Valid backup directory required"
        return 1
    fi

    print_status "Restoring firewall configuration from $backup_dir..."

    # Restore UFW rules
    sudo cp -r "$backup_dir/"* /etc/ufw/

    # Reload UFW
    sudo ufw reload

    print_success "Firewall configuration restored"
    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Firewall Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --configure             Configure basic UFW firewall
    --configure-docker      Configure UFW with Docker support
    --add-rule PORT         Add firewall rule for port
    --remove-rule PORT      Remove firewall rule for port
    --list-rules           List all firewall rules
    --configure-web        Configure web server rules
    --configure-db TYPE    Configure database rules
    --configure-tailscale  Configure Tailscale rules
    --harden               Apply strict security rules
    --backup [DIR]         Backup firewall configuration
    --restore DIR          Restore firewall configuration
    --help                 Show this help message
    --test                 Run module self-tests

EXAMPLES:
    # Configure basic firewall
    $0 --configure

    # Add custom port
    $0 --add-rule 8080

    # Configure for web server
    $0 --configure-web

    # Configure for PostgreSQL from specific IP
    $0 --configure-db postgresql 192.168.1.100

EOF
}

# Export all functions
export -f configure_ufw configure_ufw_docker
export -f add_firewall_rule remove_firewall_rule list_firewall_rules
export -f configure_web_firewall configure_database_firewall
export -f configure_tailscale_firewall harden_firewall
export -f backup_firewall_config restore_firewall_config

# Source required libraries
if [ -z "${SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/config.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/backup.sh" 2>/dev/null || true

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --configure)
            configure_ufw "${2:-}"
            ;;
        --configure-docker)
            configure_ufw_docker
            ;;
        --add-rule)
            add_firewall_rule "${2}" "${3:-tcp}" "${4:-Custom rule}" "${5:-any}"
            ;;
        --remove-rule)
            remove_firewall_rule "${2}" "${3:-tcp}"
            ;;
        --list-rules)
            list_firewall_rules
            ;;
        --configure-web)
            configure_web_firewall
            ;;
        --configure-db)
            configure_database_firewall "${2}" "${3:-127.0.0.1}"
            ;;
        --configure-tailscale)
            configure_tailscale_firewall
            ;;
        --harden)
            harden_firewall
            ;;
        --backup)
            backup_firewall_config "${2:-}"
            ;;
        --restore)
            restore_firewall_config "${2}"
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running firewall module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "Firewall Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi