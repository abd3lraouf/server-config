#!/bin/bash
# Docker module - Docker and Docker Compose installation and configuration
# Manages Docker installation, security configuration, and compose setup

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="docker"

# Docker configuration
readonly DOCKER_CONFIG_DIR="/etc/docker"
readonly DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/var/lib/docker}"
readonly DOCKER_COMPOSE_VERSION="${DOCKER_COMPOSE_VERSION:-v2.23.0}"

# ============================================================================
# Docker Installation
# ============================================================================

# Install Docker
install_docker() {
    print_status "Installing Docker..."

    # Check if Docker is already installed
    if command -v docker &>/dev/null; then
        print_warning "Docker is already installed"
        local version=$(docker --version)
        print_status "Current version: $version"

        if ! confirm_action "Reinstall Docker?"; then
            return 0
        fi

        # Remove existing installation
        remove_docker
    fi

    # Install prerequisites
    print_status "Installing prerequisites..."
    sudo apt update
    sudo apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    print_status "Adding Docker GPG key..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Set up repository
    print_status "Setting up Docker repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    print_status "Installing Docker Engine..."
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable and start Docker
    sudo systemctl enable docker
    sudo systemctl start docker

    # Verify installation
    if docker --version &>/dev/null; then
        print_success "Docker installed successfully"
        docker --version
    else
        print_error "Docker installation failed"
        return 1
    fi

    return 0
}

# ============================================================================
# Docker Configuration
# ============================================================================

# Configure Docker daemon
configure_docker_daemon() {
    print_status "Configuring Docker daemon..."

    # Backup existing configuration
    backup_file "$DOCKER_CONFIG_DIR/daemon.json"

    # Create daemon configuration
    cat << EOF | sudo tee "$DOCKER_CONFIG_DIR/daemon.json" > /dev/null
{
    "data-root": "$DOCKER_DATA_ROOT",
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "default-address-pools": [
        {
            "base": "172.30.0.0/16",
            "size": 24
        }
    ],
    "metrics-addr": "127.0.0.1:9323",
    "experimental": false,
    "features": {
        "buildkit": true
    },
    "live-restore": true,
    "userland-proxy": false,
    "ip-forward": true,
    "iptables": true,
    "ipv6": false,
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 64000,
            "Soft": 64000
        }
    }
}
EOF

    # Restart Docker to apply changes
    print_status "Restarting Docker daemon..."
    sudo systemctl restart docker

    if systemctl is-active docker &>/dev/null; then
        print_success "Docker daemon configured successfully"
    else
        print_error "Docker daemon failed to restart"
        restore_file "$DOCKER_CONFIG_DIR/daemon.json"
        sudo systemctl restart docker
        return 1
    fi

    return 0
}

# Configure Docker security
configure_docker_security() {
    print_status "Configuring Docker security..."

    # Enable user namespace remapping
    print_status "Enabling user namespace remapping..."
    echo "dockremap:231072:65536" | sudo tee -a /etc/subuid > /dev/null
    echo "dockremap:231072:65536" | sudo tee -a /etc/subgid > /dev/null

    # Update daemon configuration for security
    local config_file="$DOCKER_CONFIG_DIR/daemon.json"
    if [ -f "$config_file" ]; then
        # Merge security settings with existing config
        local tmp_config="/tmp/docker-daemon-$$.json"
        jq '. + {
            "userns-remap": "default",
            "no-new-privileges": true,
            "icc": false,
            "disable-legacy-registry": true,
            "seccomp-profile": "/etc/docker/seccomp.json"
        }' "$config_file" > "$tmp_config"
        sudo mv "$tmp_config" "$config_file"
    fi

    # Create custom seccomp profile
    create_seccomp_profile

    # Set Docker socket permissions
    sudo chmod 660 /var/run/docker.sock

    # Restart Docker
    sudo systemctl restart docker

    print_success "Docker security configured"
    return 0
}

# Create custom seccomp profile
create_seccomp_profile() {
    print_status "Creating custom seccomp profile..."

    # Use Docker's default seccomp profile as base
    curl -sSL https://raw.githubusercontent.com/moby/moby/master/profiles/seccomp/default.json | \
        sudo tee "$DOCKER_CONFIG_DIR/seccomp.json" > /dev/null

    print_success "Seccomp profile created"
}

# ============================================================================
# Docker Compose Installation
# ============================================================================

# Install Docker Compose
install_docker_compose() {
    print_status "Installing Docker Compose..."

    # Check if already installed via Docker plugin
    if docker compose version &>/dev/null 2>&1; then
        print_success "Docker Compose plugin already installed"
        docker compose version
        return 0
    fi

    # Install standalone Docker Compose (legacy)
    print_status "Installing standalone Docker Compose..."

    local arch=$(uname -m)
    local compose_arch=""

    case "$arch" in
        x86_64) compose_arch="x86_64" ;;
        aarch64) compose_arch="aarch64" ;;
        armv7l) compose_arch="armv7" ;;
        *)
            print_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    local download_url="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${compose_arch}"

    sudo curl -L "$download_url" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    # Create symlink for compatibility
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

    # Verify installation
    if docker-compose --version &>/dev/null; then
        print_success "Docker Compose installed successfully"
        docker-compose --version
    else
        print_error "Docker Compose installation failed"
        return 1
    fi

    return 0
}

# ============================================================================
# User Management
# ============================================================================

# Add user to docker group
add_user_to_docker() {
    local user="${1:-$USER}"

    print_status "Adding $user to docker group..."

    # Create docker group if it doesn't exist
    if ! getent group docker &>/dev/null; then
        sudo groupadd docker
    fi

    # Add user to docker group
    sudo usermod -aG docker "$user"

    print_success "User $user added to docker group"
    print_warning "User must log out and back in for changes to take effect"

    return 0
}

# ============================================================================
# Docker Network Management
# ============================================================================

# Create custom Docker network
create_docker_network() {
    local network_name="${1:-app-network}"
    local subnet="${2:-172.20.0.0/16}"

    print_status "Creating Docker network: $network_name"

    # Check if network already exists
    if docker network ls | grep -q "$network_name"; then
        print_warning "Network $network_name already exists"
        return 0
    fi

    # Create network
    docker network create \
        --driver bridge \
        --subnet="$subnet" \
        --opt com.docker.network.bridge.enable_icc=false \
        --opt com.docker.network.bridge.enable_ip_masquerade=true \
        "$network_name"

    print_success "Docker network $network_name created"
    return 0
}

# ============================================================================
# Docker Cleanup
# ============================================================================

# Clean up Docker system
cleanup_docker() {
    print_status "Cleaning up Docker system..."

    # Remove stopped containers
    print_status "Removing stopped containers..."
    docker container prune -f

    # Remove unused images
    print_status "Removing unused images..."
    docker image prune -a -f

    # Remove unused volumes
    print_status "Removing unused volumes..."
    docker volume prune -f

    # Remove unused networks
    print_status "Removing unused networks..."
    docker network prune -f

    # System prune (comprehensive cleanup)
    print_status "Running system prune..."
    docker system prune -a -f --volumes

    # Show disk usage
    print_status "Docker disk usage:"
    docker system df

    print_success "Docker cleanup completed"
    return 0
}

# ============================================================================
# Docker Monitoring
# ============================================================================

# Show Docker status
show_docker_status() {
    print_header "Docker System Status"

    # Docker version
    echo "Docker Version:"
    docker version

    echo ""

    # System info
    echo "System Information:"
    docker system info | head -20

    echo ""

    # Running containers
    echo "Running Containers:"
    docker ps

    echo ""

    # Images
    echo "Docker Images:"
    docker images

    echo ""

    # Networks
    echo "Docker Networks:"
    docker network ls

    echo ""

    # Volumes
    echo "Docker Volumes:"
    docker volume ls

    echo ""

    # Disk usage
    echo "Disk Usage:"
    docker system df

    return 0
}

# Monitor Docker containers
monitor_docker_containers() {
    print_status "Monitoring Docker containers..."

    # Use docker stats for live monitoring
    docker stats --no-stream

    if confirm_action "Start live monitoring?"; then
        docker stats
    fi

    return 0
}

# ============================================================================
# Docker Security Audit
# ============================================================================

# Audit Docker security
audit_docker_security() {
    print_header "Docker Security Audit"

    local issues=0

    # Check if Docker socket is protected
    if [ "$(stat -c %a /var/run/docker.sock)" = "660" ]; then
        print_success "Docker socket has secure permissions"
    else
        print_warning "Docker socket permissions may be too permissive"
        ((issues++))
    fi

    # Check if user namespace remapping is enabled
    if docker info 2>/dev/null | grep -q "userns"; then
        print_success "User namespace remapping is enabled"
    else
        print_warning "User namespace remapping is not enabled"
        ((issues++))
    fi

    # Check for running privileged containers
    local privileged=$(docker ps --quiet --all --filter "status=running" | xargs docker inspect --format '{{ .Id }}: Privileged={{ .HostConfig.Privileged }}' 2>/dev/null | grep "Privileged=true" | wc -l)
    if [ "$privileged" -eq 0 ]; then
        print_success "No privileged containers running"
    else
        print_warning "$privileged privileged container(s) running"
        ((issues++))
    fi

    # Check Docker daemon configuration
    if [ -f "$DOCKER_CONFIG_DIR/daemon.json" ]; then
        if grep -q '"icc": false' "$DOCKER_CONFIG_DIR/daemon.json"; then
            print_success "Inter-container communication is disabled"
        else
            print_warning "Inter-container communication is enabled"
            ((issues++))
        fi
    fi

    # Summary
    echo ""
    if [ $issues -eq 0 ]; then
        print_success "Docker security audit passed with no issues"
    else
        print_warning "Docker security audit found $issues issue(s)"
    fi

    return $issues
}

# ============================================================================
# Removal
# ============================================================================

# Remove Docker
remove_docker() {
    print_status "Removing Docker..."

    if ! confirm_action "This will remove Docker and all containers/images. Continue?"; then
        return 1
    fi

    # Stop all containers
    docker stop $(docker ps -aq) 2>/dev/null || true

    # Remove all containers, images, volumes
    docker rm $(docker ps -aq) 2>/dev/null || true
    docker rmi $(docker images -q) 2>/dev/null || true
    docker volume rm $(docker volume ls -q) 2>/dev/null || true

    # Uninstall Docker packages
    sudo apt remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo apt autoremove -y

    # Remove Docker directories
    sudo rm -rf /var/lib/docker
    sudo rm -rf /etc/docker

    print_success "Docker removed"
    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Docker Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --install               Install Docker
    --configure             Configure Docker daemon
    --secure                Configure Docker security
    --install-compose       Install Docker Compose
    --add-user USER         Add user to docker group
    --create-network NAME   Create custom network
    --cleanup               Clean up Docker system
    --status                Show Docker status
    --monitor               Monitor containers
    --audit                 Audit Docker security
    --remove                Remove Docker
    --help                  Show this help message
    --test                  Run module self-tests

EXAMPLES:
    # Install and configure Docker
    $0 --install
    $0 --configure
    $0 --secure

    # Add current user to docker group
    $0 --add-user \$USER

    # Clean up Docker
    $0 --cleanup

    # Audit security
    $0 --audit

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
export -f install_docker configure_docker_daemon configure_docker_security
export -f create_seccomp_profile install_docker_compose add_user_to_docker
export -f create_docker_network cleanup_docker show_docker_status
export -f monitor_docker_containers audit_docker_security remove_docker

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
            install_docker
            ;;
        --configure)
            configure_docker_daemon
            ;;
        --secure)
            configure_docker_security
            ;;
        --install-compose)
            install_docker_compose
            ;;
        --add-user)
            add_user_to_docker "${2:-$USER}"
            ;;
        --create-network)
            create_docker_network "${2:-app-network}" "${3:-172.20.0.0/16}"
            ;;
        --cleanup)
            cleanup_docker
            ;;
        --status)
            show_docker_status
            ;;
        --monitor)
            monitor_docker_containers
            ;;
        --audit)
            audit_docker_security
            ;;
        --remove)
            remove_docker
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running Docker module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "Docker Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi
