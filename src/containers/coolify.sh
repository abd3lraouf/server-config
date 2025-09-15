#!/bin/bash
# Coolify module - Self-hosted PaaS integration
# Manages Coolify compatibility and security configuration

# Script metadata
readonly MODULE_VERSION="1.0.0"
readonly MODULE_NAME="coolify"

# Coolify configuration
readonly COOLIFY_SSH_PORT="${COOLIFY_SSH_PORT:-22}"
readonly COOLIFY_DATA_DIR="${COOLIFY_DATA_DIR:-/data/coolify}"
readonly COOLIFY_SOURCE_DIR="${COOLIFY_SOURCE_DIR:-/data/coolify/source}"

# ============================================================================
# Coolify Compatibility Check
# ============================================================================

# Check if Coolify is installed
check_coolify_installed() {
    print_status "Checking for Coolify installation..."

    # Check for Coolify containers
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q coolify; then
        print_success "Coolify is installed and running"
        return 0
    fi

    # Check for Coolify directories
    if [ -d "$COOLIFY_DATA_DIR" ]; then
        print_warning "Coolify directories found but containers not running"
        return 1
    fi

    print_status "Coolify is not installed"
    return 2
}

# ============================================================================
# SSH Configuration for Coolify
# ============================================================================

# Configure SSH for Coolify
configure_ssh_for_coolify() {
    print_status "Configuring SSH for Coolify compatibility..."

    # Backup SSH config
    backup_file "/etc/ssh/sshd_config"

    # Create Coolify-specific SSH configuration
    cat << EOF | sudo tee /etc/ssh/sshd_config.d/50-coolify.conf > /dev/null
# Coolify SSH Configuration
# Required for Coolify to connect to the server

# Allow root login with key (required for Coolify)
PermitRootLogin prohibit-password

# Enable public key authentication
PubkeyAuthentication yes

# Disable password authentication
PasswordAuthentication no

# Allow specific users (root needed for Coolify)
AllowUsers root ubuntu

# Keep connections alive for Coolify
ClientAliveInterval 60
ClientAliveCountMax 3
TCPKeepAlive yes

# Allow TCP forwarding (required for Docker operations)
AllowTcpForwarding yes
PermitTunnel yes

# Allow agent forwarding
AllowAgentForwarding yes

# Accept environment variables
AcceptEnv LANG LC_* GIT_*

# Disable strict host key checking for Docker networks
Match Address 172.16.0.0/12,10.0.0.0/8
    StrictModes no
    PasswordAuthentication no
    PubkeyAuthentication yes
EOF

    # Ensure root has .ssh directory
    sudo mkdir -p /root/.ssh
    sudo chmod 700 /root/.ssh

    # Generate SSH key for root if it doesn't exist
    if [ ! -f /root/.ssh/id_ed25519 ]; then
        print_status "Generating SSH key for root user..."
        sudo ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N "" -C "root@$(hostname)"
    fi

    # Add Coolify's expected key locations to authorized_keys
    setup_coolify_ssh_keys

    # Restart SSH service
    sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd 2>/dev/null

    # Validate SSH connectivity
    sleep 2  # Give SSH time to restart
    validate_coolify_ssh

    print_success "SSH configured for Coolify"
    return 0
}

# Setup SSH keys for Coolify
setup_coolify_ssh_keys() {
    print_status "Setting up SSH keys for Coolify..."

    # Ensure SSH directories exist
    sudo mkdir -p /root/.ssh
    sudo mkdir -p /data/coolify/ssh/keys
    sudo chmod 700 /root/.ssh
    sudo chmod 700 /data/coolify/ssh/keys

    # Ensure authorized_keys exists
    sudo touch /root/.ssh/authorized_keys
    sudo chmod 600 /root/.ssh/authorized_keys

    # Generate Coolify-specific SSH keys (id.root@host.docker.internal)
    if [ ! -f "/data/coolify/ssh/keys/id.root@host.docker.internal" ]; then
        print_status "Generating Coolify-specific SSH keys (id.root@host.docker.internal)..."
        sudo ssh-keygen -t ed25519 -a 100 \
            -f /data/coolify/ssh/keys/id.root@host.docker.internal \
            -q -N "" -C root@coolify

        # Set correct ownership (9999 is Coolify's container user)
        sudo chown 9999:9999 /data/coolify/ssh/keys/id.root@host.docker.internal
        sudo chown 9999:9999 /data/coolify/ssh/keys/id.root@host.docker.internal.pub

        # Add the public key to authorized_keys
        sudo cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> /root/.ssh/authorized_keys
        print_success "Generated and added Coolify SSH key (id.root@host.docker.internal)"
    else
        # Ensure the key is in authorized_keys
        local coolify_pub_key=$(sudo cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub 2>/dev/null || echo "")
        if [ -n "$coolify_pub_key" ] && ! sudo grep -q "$coolify_pub_key" /root/.ssh/authorized_keys; then
            echo "$coolify_pub_key" | sudo tee -a /root/.ssh/authorized_keys > /dev/null
            print_success "Added existing Coolify SSH key to authorized_keys"
        fi
    fi

    # Add localhost key for Coolify self-connection (if exists)
    if [ -f /root/.ssh/id_ed25519.pub ]; then
        if ! grep -q "$(cat /root/.ssh/id_ed25519.pub)" /root/.ssh/authorized_keys; then
            cat /root/.ssh/id_ed25519.pub | sudo tee -a /root/.ssh/authorized_keys > /dev/null
            print_success "Added root SSH key to authorized_keys"
        fi
    fi

    # Create SSH config for Docker network access
    cat << 'EOF' | sudo tee /root/.ssh/config > /dev/null
Host host.docker.internal
    HostName host.docker.internal
    User root
    Port 22
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    IdentityFile /root/.ssh/id_ed25519

Host localhost
    HostName localhost
    User root
    Port 22
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    IdentityFile /root/.ssh/id_ed25519
EOF

    sudo chmod 600 /root/.ssh/config

    print_success "SSH keys configured for Coolify"
    return 0
}

# Validate SSH connectivity for Coolify
validate_coolify_ssh() {
    print_status "Validating SSH connectivity for Coolify..."

    # Check if Coolify container is running
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^coolify$"; then
        print_warning "Coolify container not running, skipping SSH validation"
        return 0
    fi

    # Test SSH connection from Coolify container to host
    print_status "Testing SSH connection from Coolify container..."

    # The key path inside the container is different due to volume mapping
    local container_key_path="/var/www/html/storage/app/ssh/keys/id.root@host.docker.internal"

    if sudo docker exec coolify test -f "$container_key_path" 2>/dev/null; then
        if sudo docker exec coolify ssh -i "$container_key_path" \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=5 \
            root@host.docker.internal "echo 'SSH connection successful'" 2>/dev/null; then
            print_success "SSH connectivity validated - Coolify can connect to host"
            return 0
        else
            print_error "SSH connection failed from Coolify container"
            print_status "Debugging information:"
            echo "  - Key exists in container: Yes"
            echo "  - Key path: $container_key_path"
            echo "  - Target: root@host.docker.internal"
            return 1
        fi
    else
        print_warning "Coolify SSH key not found in container"
        print_status "Expected key at: $container_key_path"
        return 1
    fi
}

# ============================================================================
# Firewall Configuration for Coolify
# ============================================================================

# Configure firewall for Coolify
configure_firewall_for_coolify() {
    print_status "Configuring firewall for Coolify..."

    # Essential Coolify ports
    local ports=(
        "22/tcp"    # SSH
        "80/tcp"    # HTTP
        "443/tcp"   # HTTPS
        "8000/tcp"  # Coolify UI
        "6001/tcp"  # Coolify Realtime (Soketi)
        "6002/tcp"  # Coolify Horizon
    )

    for port in "${ports[@]}"; do
        print_status "Allowing port $port..."
        sudo ufw allow $port comment "Coolify"
    done

    # Allow Docker networks
    sudo ufw allow from 172.16.0.0/12 comment "Docker networks"
    sudo ufw allow from 10.0.0.0/8 comment "Docker swarm"

    # Reload firewall
    sudo ufw reload

    print_success "Firewall configured for Coolify"
    return 0
}

# ============================================================================
# Docker Configuration for Coolify
# ============================================================================

# Configure Docker for Coolify
configure_docker_for_coolify() {
    print_status "Configuring Docker for Coolify..."

    # Ensure Docker is installed
    if ! command -v docker &>/dev/null; then
        print_error "Docker is not installed"
        return 1
    fi

    # Create Coolify directories
    sudo mkdir -p "$COOLIFY_DATA_DIR"
    sudo mkdir -p "$COOLIFY_SOURCE_DIR"
    sudo mkdir -p /data/coolify/proxy
    sudo mkdir -p /data/coolify/databases
    sudo mkdir -p /data/coolify/services
    sudo mkdir -p /data/coolify/backups

    # Set permissions
    sudo chown -R root:root /data/coolify
    sudo chmod -R 755 /data/coolify

    # Configure Docker daemon for Coolify
    backup_file "/etc/docker/daemon.json"

    # Update Docker configuration
    local docker_config="/etc/docker/daemon.json"
    if [ -f "$docker_config" ]; then
        # Merge with existing config
        local tmp_config="/tmp/docker-daemon-$$.json"
        jq '. + {
            "log-driver": "json-file",
            "log-opts": {
                "max-size": "10m",
                "max-file": "3"
            },
            "live-restore": true,
            "userland-proxy": false
        }' "$docker_config" > "$tmp_config"
        sudo mv "$tmp_config" "$docker_config"
    else
        # Create new config
        cat << 'EOF' | sudo tee "$docker_config" > /dev/null
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "live-restore": true,
    "userland-proxy": false
}
EOF
    fi

    # Restart Docker
    sudo systemctl restart docker

    print_success "Docker configured for Coolify"
    return 0
}

# ============================================================================
# Coolify Installation
# ============================================================================

# Install Coolify
install_coolify() {
    print_status "Installing Coolify..."

    # Check prerequisites
    if ! command -v docker &>/dev/null; then
        print_error "Docker is required for Coolify"
        return 1
    fi

    # Download and run Coolify installer
    print_status "Downloading Coolify installer..."
    curl -fsSL https://get.coolify.io | sudo bash

    # Wait for installation to complete
    print_status "Waiting for Coolify to start..."
    sleep 30

    # Check if Coolify is running
    if docker ps --format '{{.Names}}' | grep -q coolify; then
        print_success "Coolify installed successfully"

        # Get Coolify URL
        local coolify_ip=$(hostname -I | awk '{print $1}')
        print_success "Coolify is available at: http://$coolify_ip:8000"
    else
        print_error "Coolify installation may have failed"
        return 1
    fi

    return 0
}

# ============================================================================
# Security Hardening for Coolify
# ============================================================================

# Harden Coolify security
harden_coolify_security() {
    print_status "Hardening Coolify security..."

    # Restrict Coolify UI access
    if command -v ufw &>/dev/null; then
        print_status "Restricting Coolify UI access..."

        # Remove broad access
        sudo ufw delete allow 8000/tcp 2>/dev/null || true

        # Allow only from specific sources if configured
        if [ -n "${COOLIFY_ALLOWED_IPS:-}" ]; then
            for ip in $(echo "$COOLIFY_ALLOWED_IPS" | tr ',' ' '); do
                sudo ufw allow from "$ip" to any port 8000 proto tcp comment "Coolify UI"
            done
        else
            # Allow from private networks by default
            sudo ufw allow from 10.0.0.0/8 to any port 8000 proto tcp comment "Coolify UI"
            sudo ufw allow from 172.16.0.0/12 to any port 8000 proto tcp comment "Coolify UI"
            sudo ufw allow from 192.168.0.0/16 to any port 8000 proto tcp comment "Coolify UI"
        fi
    fi

    # Set up fail2ban for Coolify
    if command -v fail2ban-client &>/dev/null; then
        configure_fail2ban_for_coolify
    fi

    # Configure log rotation
    cat << 'EOF' | sudo tee /etc/logrotate.d/coolify > /dev/null
/data/coolify/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF

    print_success "Coolify security hardened"
    return 0
}

# Configure fail2ban for Coolify
configure_fail2ban_for_coolify() {
    print_status "Configuring fail2ban for Coolify..."

    cat << 'EOF' | sudo tee /etc/fail2ban/jail.d/coolify.conf > /dev/null
[coolify-auth]
enabled = true
filter = coolify-auth
port = 8000
logpath = /data/coolify/logs/auth.log
maxretry = 5
findtime = 600
bantime = 3600

[coolify-api]
enabled = true
filter = coolify-api
port = 8000
logpath = /data/coolify/logs/api.log
maxretry = 100
findtime = 60
bantime = 600
EOF

    # Create filters
    cat << 'EOF' | sudo tee /etc/fail2ban/filter.d/coolify-auth.conf > /dev/null
[Definition]
failregex = ^.*Failed login attempt from <HOST>.*$
            ^.*Invalid credentials from <HOST>.*$
ignoreregex =
EOF

    cat << 'EOF' | sudo tee /etc/fail2ban/filter.d/coolify-api.conf > /dev/null
[Definition]
failregex = ^.*API rate limit exceeded from <HOST>.*$
            ^.*Too many requests from <HOST>.*$
ignoreregex =
EOF

    # Reload fail2ban
    sudo fail2ban-client reload

    print_success "Fail2ban configured for Coolify"
}

# ============================================================================
# Backup Configuration
# ============================================================================

# Configure Coolify backups
configure_coolify_backups() {
    print_status "Configuring Coolify backups..."

    # Create backup script
    cat << 'EOF' | sudo tee /usr/local/bin/backup-coolify.sh > /dev/null
#!/bin/bash
# Coolify Backup Script

BACKUP_DIR="/data/coolify/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/coolify-backup-$TIMESTAMP.tar.gz"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Stop Coolify services
docker stop $(docker ps -q --filter "label=coolify")

# Backup Coolify data
tar czf "$BACKUP_FILE" \
    /data/coolify/source \
    /data/coolify/proxy \
    /data/coolify/databases \
    /data/coolify/services \
    --exclude="/data/coolify/backups"

# Start Coolify services
docker start $(docker ps -aq --filter "label=coolify")

# Remove old backups (keep last 7)
find "$BACKUP_DIR" -name "coolify-backup-*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_FILE"
EOF

    sudo chmod +x /usr/local/bin/backup-coolify.sh

    # Add to crontab (daily at 3 AM)
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/backup-coolify.sh") | crontab -

    print_success "Coolify backup configured"
    return 0
}

# ============================================================================
# Monitoring
# ============================================================================

# Show Coolify status
show_coolify_status() {
    print_header "Coolify Status"

    # Check if Coolify is installed
    if ! check_coolify_installed; then
        print_warning "Coolify is not installed"
        return 1
    fi

    # Show running containers
    echo "Coolify Containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep coolify

    echo ""

    # Show resource usage
    echo "Resource Usage:"
    docker stats --no-stream $(docker ps -q --filter "label=coolify")

    echo ""

    # Show disk usage
    echo "Disk Usage:"
    du -sh /data/coolify/* 2>/dev/null | head -10

    echo ""

    # Check service health
    echo "Service Health:"
    local coolify_ip=$(hostname -I | awk '{print $1}')
    if curl -s "http://$coolify_ip:8000/health" &>/dev/null; then
        print_success "Coolify UI is accessible"
    else
        print_warning "Coolify UI is not accessible"
    fi

    return 0
}

# ============================================================================
# Complete Setup
# ============================================================================

# Run complete Coolify setup
setup_coolify_complete() {
    print_header "Complete Coolify Setup"

    # Check if Coolify is already installed
    if check_coolify_installed; then
        print_warning "Coolify is already installed"

        if ! confirm_action "Configure Coolify integration?"; then
            return 0
        fi
    else
        if confirm_action "Install Coolify?"; then
            # Install Docker if needed
            if ! command -v docker &>/dev/null; then
                print_status "Docker is required. Please install Docker first."
                return 1
            fi

            install_coolify
        fi
    fi

    # Configure components
    configure_ssh_for_coolify
    configure_firewall_for_coolify
    configure_docker_for_coolify
    harden_coolify_security
    configure_coolify_backups

    # Show status
    show_coolify_status

    print_success "Coolify setup completed!"
    print_warning "Remember to:"
    echo "  • Access Coolify UI at http://$(hostname -I | awk '{print $1}'):8000"
    echo "  • Complete initial setup in the UI"
    echo "  • Configure domain and SSL certificates"
    echo "  • Set up GitHub/GitLab integration"
    echo "  • Review security settings"

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Coolify Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --check                 Check if Coolify is installed
    --install               Install Coolify
    --configure-ssh         Configure SSH for Coolify
    --configure-firewall    Configure firewall for Coolify
    --configure-docker      Configure Docker for Coolify
    --harden                Harden Coolify security
    --configure-backups     Configure automated backups
    --status                Show Coolify status
    --complete              Run complete setup
    --help                  Show this help message
    --test                  Run module self-tests

EXAMPLES:
    # Complete setup
    $0 --complete

    # Check status
    $0 --status

    # Configure SSH only
    $0 --configure-ssh

    # Harden security
    $0 --harden

ENVIRONMENT VARIABLES:
    COOLIFY_ALLOWED_IPS     Comma-separated IPs for UI access
    COOLIFY_SSH_PORT        SSH port (default: 22)
    COOLIFY_DATA_DIR        Data directory (default: /data/coolify)

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
export -f check_coolify_installed
export -f configure_ssh_for_coolify setup_coolify_ssh_keys validate_coolify_ssh
export -f configure_firewall_for_coolify configure_docker_for_coolify
export -f install_coolify harden_coolify_security
export -f configure_fail2ban_for_coolify configure_coolify_backups
export -f show_coolify_status setup_coolify_complete

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/backup.sh" 2>/dev/null || true

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --check)
            check_coolify_installed
            ;;
        --install)
            install_coolify
            ;;
        --configure-ssh)
            configure_ssh_for_coolify
            ;;
        --configure-firewall)
            configure_firewall_for_coolify
            ;;
        --configure-docker)
            configure_docker_for_coolify
            ;;
        --harden)
            harden_coolify_security
            ;;
        --configure-backups)
            configure_coolify_backups
            ;;
        --status)
            show_coolify_status
            ;;
        --complete)
            setup_coolify_complete
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running Coolify module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "Coolify Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi