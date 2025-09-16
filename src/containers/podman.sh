#!/bin/bash
# Podman Container Runtime module - Rootless, daemonless container management
# OCI-compliant alternative to Docker with enhanced security features

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="podman-container"

# Configuration
readonly PODMAN_VERSION="latest"  # or specific version like "4.7.0"
readonly PODMAN_CONFIG_DIR="/etc/containers"
readonly PODMAN_STORAGE_DIR="/var/lib/containers"
readonly PODMAN_USER_CONFIG_DIR="$HOME/.config/containers"
readonly COMPOSE_VERSION="latest"

# ============================================================================
# Installation and Setup
# ============================================================================

# Install Podman
install_podman() {
    print_header "Installing Podman Container Runtime"

    # Check if already installed
    if command -v podman &>/dev/null; then
        print_warning "Podman is already installed"
        podman --version
        return 0
    fi

    # Detect OS and version
    local os_id=$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')
    local os_version=$(lsb_release -sr 2>/dev/null)

    print_status "Installing Podman for $os_id $os_version..."

    case "$os_id" in
        ubuntu)
            install_podman_ubuntu "$os_version"
            ;;
        debian)
            install_podman_debian "$os_version"
            ;;
        fedora|rhel|centos)
            install_podman_rhel
            ;;
        *)
            print_error "Unsupported OS: $os_id"
            return 1
            ;;
    esac

    # Verify installation
    if command -v podman &>/dev/null; then
        print_success "Podman installed successfully"
        podman --version
    else
        print_error "Failed to install Podman"
        return 1
    fi

    return 0
}

# Install Podman on Ubuntu
install_podman_ubuntu() {
    local version="$1"

    # Update package list
    sudo apt update

    # For Ubuntu 20.10 and newer
    if [[ "${version%%.*}" -ge 20 ]]; then
        print_status "Installing Podman from official Ubuntu repository..."
        sudo apt install -y podman podman-docker
    else
        # For older Ubuntu versions, use Kubic repository
        print_status "Adding Kubic repository for Podman..."

        # Add repository
        echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${version}/ /" | \
            sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list

        # Add GPG key
        curl -L "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${version}/Release.key" | \
            sudo apt-key add -

        # Update and install
        sudo apt update
        sudo apt install -y podman
    fi

    # Install additional tools
    sudo apt install -y \
        buildah \
        skopeo \
        containernetworking-plugins \
        uidmap \
        slirp4netns \
        fuse-overlayfs
}

# Install Podman on Debian
install_podman_debian() {
    local version="$1"

    print_status "Installing Podman on Debian..."

    # Add repository
    echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/Debian_${version}/ /" | \
        sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list

    # Add GPG key
    curl -L "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/Debian_${version}/Release.key" | \
        sudo apt-key add -

    # Update and install
    sudo apt update
    sudo apt install -y podman buildah skopeo
}

# Install Podman on RHEL-based systems
install_podman_rhel() {
    print_status "Installing Podman on RHEL-based system..."
    sudo dnf install -y podman podman-docker buildah skopeo
}

# ============================================================================
# Configuration
# ============================================================================

# Configure Podman
configure_podman() {
    print_status "Configuring Podman..."

    # Create configuration directories
    sudo mkdir -p "$PODMAN_CONFIG_DIR"
    sudo mkdir -p "$PODMAN_CONFIG_DIR/registries.conf.d"
    sudo mkdir -p "$PODMAN_CONFIG_DIR/policy.d"

    # Configure registries
    configure_registries

    # Configure storage
    configure_storage

    # Configure network
    configure_network

    # Configure security
    configure_security

    # Setup rootless mode
    setup_rootless_mode

    print_success "Podman configured"
    return 0
}

# Configure container registries
configure_registries() {
    print_status "Configuring container registries..."

    cat << 'EOF' | sudo tee "$PODMAN_CONFIG_DIR/registries.conf" > /dev/null
# Container Registries Configuration

# Search registries
unqualified-search-registries = ["docker.io", "quay.io", "gcr.io"]

# Docker Hub
[[registry]]
location = "docker.io"
insecure = false

# Red Hat Quay
[[registry]]
location = "quay.io"
insecure = false

# Google Container Registry
[[registry]]
location = "gcr.io"
insecure = false

# GitHub Container Registry
[[registry]]
location = "ghcr.io"
insecure = false

# Short name aliases
[aliases]
"debian" = "docker.io/library/debian"
"ubuntu" = "docker.io/library/ubuntu"
"alpine" = "docker.io/library/alpine"
"nginx" = "docker.io/library/nginx"
"redis" = "docker.io/library/redis"
"postgres" = "docker.io/library/postgres"
"mysql" = "docker.io/library/mysql"
EOF

    print_success "Registries configured"
}

# Configure storage
configure_storage() {
    print_status "Configuring storage driver..."

    cat << 'EOF' | sudo tee "$PODMAN_CONFIG_DIR/storage.conf" > /dev/null
# Storage Configuration

[storage]
# Default storage driver
driver = "overlay"

# Storage location
graphroot = "/var/lib/containers/storage"
runroot = "/run/containers/storage"

[storage.options]
# Enable additional image stores
additionalimagestores = []

# Overlay storage options
[storage.options.overlay]
# Enable metacopy
metacopy = true

# Mount options
mountopt = "nodev,metacopy=on"

# Size for container root filesystem
size = "10G"

# UID/GID mappings for rootless containers
[storage.options.thinpool]
EOF

    print_success "Storage configured"
}

# Configure network
configure_network() {
    print_status "Configuring Podman network..."

    # Create default network configuration
    cat << 'EOF' | sudo tee "$PODMAN_CONFIG_DIR/cni/87-podman.conflist" > /dev/null
{
    "cniVersion": "0.4.0",
    "name": "podman",
    "plugins": [
        {
            "type": "bridge",
            "bridge": "cni-podman0",
            "isGateway": true,
            "ipMasq": true,
            "hairpinMode": true,
            "ipam": {
                "type": "host-local",
                "routes": [{"dst": "0.0.0.0/0"}],
                "ranges": [
                    [{"subnet": "10.88.0.0/16", "gateway": "10.88.0.1"}]
                ]
            }
        },
        {
            "type": "portmap",
            "capabilities": {
                "portMappings": true
            }
        },
        {
            "type": "firewall"
        },
        {
            "type": "tuning"
        }
    ]
}
EOF

    # Enable IP forwarding for containers
    echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/99-containers.conf
    echo "net.ipv6.conf.all.forwarding = 1" | sudo tee -a /etc/sysctl.d/99-containers.conf
    sudo sysctl -p /etc/sysctl.d/99-containers.conf

    print_success "Network configured"
}

# Configure security
configure_security() {
    print_status "Configuring security policies..."

    # Create default security policy
    cat << 'EOF' | sudo tee "$PODMAN_CONFIG_DIR/policy.json" > /dev/null
{
    "default": [
        {
            "type": "insecureAcceptAnything"
        }
    ],
    "transports": {
        "docker": {
            "docker.io": [
                {
                    "type": "signedBy",
                    "keyType": "GPGKeys",
                    "keyPath": "/etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release"
                }
            ]
        },
        "docker-daemon": {
            "": [
                {
                    "type": "insecureAcceptAnything"
                }
            ]
        },
        "atomic": {
            "": [
                {
                    "type": "insecureAcceptAnything"
                }
            ]
        }
    }
}
EOF

    # Configure seccomp profile
    cat << 'EOF' | sudo tee "$PODMAN_CONFIG_DIR/seccomp.json" > /dev/null
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "defaultErrnoRet": 1,
    "archMap": [
        {
            "architecture": "SCMP_ARCH_X86_64",
            "subArchitectures": [
                "SCMP_ARCH_X86",
                "SCMP_ARCH_X32"
            ]
        },
        {
            "architecture": "SCMP_ARCH_AARCH64",
            "subArchitectures": [
                "SCMP_ARCH_ARM"
            ]
        }
    ],
    "syscalls": [
        {
            "names": [
                "accept",
                "accept4",
                "access",
                "alarm",
                "bind",
                "brk",
                "capget",
                "capset",
                "chdir",
                "chmod",
                "chown",
                "chown32",
                "clock_getres",
                "clock_gettime",
                "clock_nanosleep",
                "close",
                "connect",
                "copy_file_range",
                "creat",
                "dup",
                "dup2",
                "dup3",
                "epoll_create",
                "epoll_create1",
                "epoll_ctl",
                "epoll_ctl_old",
                "epoll_pwait",
                "epoll_wait"
            ],
            "action": "SCMP_ACT_ALLOW"
        }
    ]
}
EOF

    print_success "Security policies configured"
}

# ============================================================================
# Rootless Mode
# ============================================================================

# Setup rootless mode
setup_rootless_mode() {
    print_header "Setting up Rootless Podman"

    local username="${MAIN_USER:-$SUDO_USER}"

    if [ -z "$username" ] || [ "$username" = "root" ]; then
        print_warning "No non-root user detected, skipping rootless setup"
        return 0
    fi

    print_status "Configuring rootless mode for user: $username"

    # Enable lingering for user systemd services
    sudo loginctl enable-linger "$username"

    # Configure subuid and subgid
    if ! grep -q "^$username:" /etc/subuid; then
        echo "$username:100000:65536" | sudo tee -a /etc/subuid
    fi

    if ! grep -q "^$username:" /etc/subgid; then
        echo "$username:100000:65536" | sudo tee -a /etc/subgid
    fi

    # Create user configuration directory
    sudo -u "$username" mkdir -p "/home/$username/.config/containers"

    # Create user storage configuration
    cat << EOF | sudo -u "$username" tee "/home/$username/.config/containers/storage.conf" > /dev/null
[storage]
driver = "overlay"
graphroot = "/home/$username/.local/share/containers/storage"
runroot = "/run/user/$(id -u $username)/containers"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
EOF

    # Setup systemd user services directory
    sudo -u "$username" mkdir -p "/home/$username/.config/systemd/user"

    # Create podman socket service for Docker compatibility
    cat << 'EOF' | sudo -u "$username" tee "/home/$username/.config/systemd/user/podman.socket" > /dev/null
[Unit]
Description=Podman API Socket
Documentation=man:podman-api(1)

[Socket]
ListenStream=%t/podman/podman.sock
SocketMode=0660

[Install]
WantedBy=sockets.target
EOF

    cat << 'EOF' | sudo -u "$username" tee "/home/$username/.config/systemd/user/podman.service" > /dev/null
[Unit]
Description=Podman API Service
Requires=podman.socket
After=podman.socket
Documentation=man:podman-api(1)
StartLimitIntervalSec=0

[Service]
Type=exec
KillMode=process
Environment=LOGGING="--log-level=info"
ExecStart=/usr/bin/podman $LOGGING system service

[Install]
WantedBy=default.target
EOF

    # Enable podman socket for user
    sudo -u "$username" systemctl --user daemon-reload
    sudo -u "$username" systemctl --user enable podman.socket

    print_success "Rootless mode configured for $username"
    return 0
}

# ============================================================================
# Docker Compatibility
# ============================================================================

# Setup Docker compatibility
setup_docker_compatibility() {
    print_header "Setting up Docker Compatibility"

    # Install podman-docker package if not already installed
    if ! dpkg -l | grep -q podman-docker; then
        print_status "Installing podman-docker compatibility package..."
        sudo apt install -y podman-docker
    fi

    # Create docker command symlink
    if [ ! -e /usr/bin/docker ]; then
        sudo ln -s /usr/bin/podman /usr/bin/docker
    fi

    # Setup Docker socket compatibility
    print_status "Setting up Docker socket compatibility..."

    # Create systemd service for root
    cat << 'EOF' | sudo tee /etc/systemd/system/podman.socket > /dev/null
[Unit]
Description=Podman API Socket
Documentation=man:podman-api(1)

[Socket]
ListenStream=/var/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF

    cat << 'EOF' | sudo tee /etc/systemd/system/podman.service > /dev/null
[Unit]
Description=Podman API Service
Requires=podman.socket
After=podman.socket
Documentation=man:podman-api(1)

[Service]
Type=exec
KillMode=process
ExecStart=/usr/bin/podman system service

[Install]
WantedBy=default.target
EOF

    # Create docker group if it doesn't exist
    if ! getent group docker &>/dev/null; then
        sudo groupadd docker
    fi

    # Add user to docker group
    local username="${MAIN_USER:-$SUDO_USER}"
    if [ -n "$username" ] && [ "$username" != "root" ]; then
        sudo usermod -aG docker "$username"
    fi

    # Enable and start podman socket
    sudo systemctl daemon-reload
    sudo systemctl enable podman.socket
    sudo systemctl start podman.socket

    # Create Docker CLI configuration directory
    sudo mkdir -p /etc/docker

    # Create daemon.json for compatibility
    cat << 'EOF' | sudo tee /etc/docker/daemon.json > /dev/null
{
    "log-driver": "journald",
    "log-opts": {
        "tag": "{{.Name}}"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "default-runtime": "crun",
    "runtimes": {
        "crun": {
            "path": "/usr/bin/crun"
        },
        "runc": {
            "path": "/usr/bin/runc"
        }
    }
}
EOF

    print_success "Docker compatibility configured"
    print_status "Docker commands will now use Podman backend"

    return 0
}

# ============================================================================
# Podman Compose
# ============================================================================

# Install Podman Compose
install_podman_compose() {
    print_header "Installing Podman Compose"

    # Check if already installed
    if command -v podman-compose &>/dev/null; then
        print_warning "Podman Compose is already installed"
        podman-compose --version
        return 0
    fi

    print_status "Installing Podman Compose..."

    # Install using pip3
    sudo pip3 install podman-compose

    # Alternative: Install from repository
    if ! command -v podman-compose &>/dev/null; then
        print_status "Installing from repository..."
        sudo apt install -y python3-podman-compose || {
            # Fallback to manual installation
            print_status "Installing from GitHub..."
            sudo curl -o /usr/local/bin/podman-compose \
                https://raw.githubusercontent.com/containers/podman-compose/main/podman_compose.py
            sudo chmod +x /usr/local/bin/podman-compose
        }
    fi

    # Create docker-compose symlink for compatibility
    if [ ! -e /usr/local/bin/docker-compose ]; then
        sudo ln -s /usr/local/bin/podman-compose /usr/local/bin/docker-compose
    fi

    # Verify installation
    if command -v podman-compose &>/dev/null; then
        print_success "Podman Compose installed successfully"
        podman-compose --version
    else
        print_error "Failed to install Podman Compose"
        return 1
    fi

    return 0
}

# ============================================================================
# Container Management
# ============================================================================

# Create systemd service for container
create_container_service() {
    local container_name="${1:-}"
    local image="${2:-}"
    local options="${3:-}"

    if [ -z "$container_name" ] || [ -z "$image" ]; then
        print_error "Usage: create_container_service <name> <image> [options]"
        return 1
    fi

    print_status "Creating systemd service for container: $container_name"

    # Generate systemd service
    podman generate systemd \
        --new \
        --name "$container_name" \
        --files \
        --restart-policy=always

    # Move service file to systemd directory
    if [ -f "container-${container_name}.service" ]; then
        sudo mv "container-${container_name}.service" /etc/systemd/system/
        sudo systemctl daemon-reload
        sudo systemctl enable "container-${container_name}.service"
        print_success "Service created: container-${container_name}.service"
    else
        print_error "Failed to generate service file"
        return 1
    fi

    return 0
}

# Setup auto-update for containers
setup_auto_update() {
    print_header "Setting up Container Auto-Update"

    # Create systemd timer for auto-updates
    cat << 'EOF' | sudo tee /etc/systemd/system/podman-auto-update.service > /dev/null
[Unit]
Description=Podman Auto Update
Documentation=man:podman-auto-update(1)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/podman auto-update
ExecStartPost=/usr/bin/podman image prune -f

[Install]
WantedBy=default.target
EOF

    cat << 'EOF' | sudo tee /etc/systemd/system/podman-auto-update.timer > /dev/null
[Unit]
Description=Podman Auto Update Timer
Documentation=man:podman-auto-update(1)

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Enable and start timer
    sudo systemctl daemon-reload
    sudo systemctl enable podman-auto-update.timer
    sudo systemctl start podman-auto-update.timer

    print_success "Auto-update configured (daily)"
    return 0
}

# ============================================================================
# Pod Management
# ============================================================================

# Create Kubernetes-style pod
create_pod() {
    local pod_name="${1:-}"
    local port_mappings="${2:-}"  # format: "8080:80,8443:443"

    if [ -z "$pod_name" ]; then
        print_error "Pod name required"
        return 1
    fi

    print_status "Creating pod: $pod_name"

    # Build podman create command
    local pod_cmd="podman pod create --name $pod_name"

    # Add port mappings if provided
    if [ -n "$port_mappings" ]; then
        IFS=',' read -ra PORTS <<< "$port_mappings"
        for port in "${PORTS[@]}"; do
            pod_cmd="$pod_cmd -p $port"
        done
    fi

    # Create pod
    if $pod_cmd; then
        print_success "Pod created: $pod_name"

        # Show pod info
        podman pod ps --filter name="$pod_name"
    else
        print_error "Failed to create pod"
        return 1
    fi

    return 0
}

# Deploy pod from YAML
deploy_pod_yaml() {
    local yaml_file="${1:-}"

    if [ -z "$yaml_file" ] || [ ! -f "$yaml_file" ]; then
        print_error "Valid YAML file required"
        return 1
    fi

    print_status "Deploying pod from YAML: $yaml_file"

    if podman play kube "$yaml_file"; then
        print_success "Pod deployed successfully"
    else
        print_error "Failed to deploy pod"
        return 1
    fi

    return 0
}

# ============================================================================
# Migration Tools
# ============================================================================

# Migrate from Docker to Podman
migrate_from_docker() {
    print_header "Migrating from Docker to Podman"

    if ! command -v docker &>/dev/null; then
        print_warning "Docker not found, nothing to migrate"
        return 0
    fi

    # Check for running Docker containers
    print_status "Checking for Docker containers..."
    local containers=$(docker ps -aq)

    if [ -n "$containers" ]; then
        print_status "Found Docker containers to migrate"

        # Export Docker containers
        for container in $containers; do
            local name=$(docker inspect --format='{{.Name}}' "$container" | sed 's/^\///')
            print_status "Migrating container: $name"

            # Export container
            docker export "$container" > "/tmp/${name}.tar"

            # Import to Podman
            podman import "/tmp/${name}.tar" "localhost/${name}:migrated"

            # Clean up
            rm -f "/tmp/${name}.tar"
        done
    fi

    # Migrate Docker images
    print_status "Migrating Docker images..."
    local images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v '<none>')

    for image in $images; do
        print_status "Migrating image: $image"

        # Save Docker image
        docker save "$image" > "/tmp/image.tar"

        # Load into Podman
        podman load < "/tmp/image.tar"

        # Clean up
        rm -f "/tmp/image.tar"
    done

    # Migrate Docker volumes
    print_status "Migrating Docker volumes..."
    local volumes=$(docker volume ls -q)

    for volume in $volumes; do
        print_status "Migrating volume: $volume"

        # Create Podman volume
        podman volume create "$volume"

        # Copy data (requires manual intervention)
        print_warning "Volume data migration requires manual copying"
    done

    print_success "Migration completed"
    print_status "Please verify migrated containers and adjust configurations as needed"

    return 0
}

# ============================================================================
# Testing and Validation
# ============================================================================

# Test Podman installation
test_podman() {
    print_header "Testing Podman Installation"

    local tests_passed=0
    local tests_failed=0

    # Test: Podman installed
    if command -v podman &>/dev/null; then
        ((tests_passed++))
        print_success "Podman is installed"
        podman --version
    else
        ((tests_failed++))
        print_error "Podman not found"
    fi

    # Test: Run hello-world container
    print_status "Testing container execution..."
    if podman run --rm docker.io/library/hello-world &>/dev/null; then
        ((tests_passed++))
        print_success "Container execution works"
    else
        ((tests_failed++))
        print_error "Container execution failed"
    fi

    # Test: Rootless mode
    if [ "$EUID" -ne 0 ]; then
        print_status "Testing rootless mode..."
        if podman run --rm docker.io/library/alpine echo "Rootless works" &>/dev/null; then
            ((tests_passed++))
            print_success "Rootless mode works"
        else
            ((tests_failed++))
            print_error "Rootless mode failed"
        fi
    fi

    # Test: Network connectivity
    print_status "Testing network connectivity..."
    if podman run --rm docker.io/library/alpine ping -c 1 google.com &>/dev/null; then
        ((tests_passed++))
        print_success "Container networking works"
    else
        ((tests_failed++))
        print_error "Container networking failed"
    fi

    # Test: Volume mounting
    print_status "Testing volume mounting..."
    local test_dir="/tmp/podman-test-$$"
    mkdir -p "$test_dir"
    echo "test" > "$test_dir/test.txt"

    if podman run --rm -v "$test_dir:/mnt:Z" docker.io/library/alpine cat /mnt/test.txt | grep -q "test"; then
        ((tests_passed++))
        print_success "Volume mounting works"
    else
        ((tests_failed++))
        print_error "Volume mounting failed"
    fi
    rm -rf "$test_dir"

    # Test: Docker compatibility
    if [ -e /usr/bin/docker ] || command -v docker &>/dev/null; then
        print_status "Testing Docker compatibility..."
        if docker --version &>/dev/null; then
            ((tests_passed++))
            print_success "Docker compatibility works"
        else
            ((tests_failed++))
            print_error "Docker compatibility failed"
        fi
    fi

    # Summary
    echo ""
    echo "Test Results:"
    echo "  Passed: $tests_passed"
    echo "  Failed: $tests_failed"

    if [ $tests_failed -eq 0 ]; then
        print_success "All tests passed!"
        return 0
    else
        print_warning "Some tests failed"
        return 1
    fi
}

# ============================================================================
# Complete Setup
# ============================================================================

# Run complete Podman setup
setup_podman_complete() {
    print_header "Complete Podman Setup"

    # Install Podman
    install_podman || return 1

    # Configure Podman
    configure_podman

    # Setup rootless mode
    setup_rootless_mode

    # Setup Docker compatibility
    if confirm_action "Setup Docker compatibility?"; then
        setup_docker_compatibility
    fi

    # Install Podman Compose
    if confirm_action "Install Podman Compose?"; then
        install_podman_compose
    fi

    # Setup auto-update
    if confirm_action "Setup container auto-update?"; then
        setup_auto_update
    fi

    # Test installation
    test_podman

    print_success "Podman setup completed!"

    echo ""
    echo "Quick Start Commands:"
    echo "  podman run -it alpine sh           # Run Alpine Linux"
    echo "  podman ps -a                        # List all containers"
    echo "  podman images                       # List images"
    echo "  podman system prune -a              # Clean up"
    echo ""
    echo "Docker Compatibility:"
    echo "  docker run -it alpine sh            # Works with Podman!"
    echo "  docker-compose up                   # Uses podman-compose"

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Podman Container Runtime Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --install               Install Podman
    --configure             Configure Podman
    --rootless              Setup rootless mode
    --docker-compat         Setup Docker compatibility
    --compose               Install Podman Compose
    --auto-update           Setup container auto-update
    --migrate               Migrate from Docker to Podman
    --test                  Test Podman installation
    --complete              Complete setup with all features
    --help                  Show this help message

CONTAINER MANAGEMENT:
    --create-service NAME IMAGE   Create systemd service for container
    --create-pod NAME [PORTS]      Create Kubernetes-style pod
    --deploy-yaml FILE             Deploy pod from YAML file

EXAMPLES:
    # Complete installation
    $0 --complete

    # Install with Docker compatibility
    $0 --install
    $0 --docker-compat

    # Create container service
    $0 --create-service nginx docker.io/nginx

    # Create pod with port mappings
    $0 --create-pod webapp "8080:80,8443:443"

ROOTLESS MODE:
    Podman can run without root privileges:
    $ podman run --rm alpine echo "Running rootless"

DOCKER COMPATIBILITY:
    After setup, Docker commands work with Podman:
    $ docker run -it alpine sh
    $ docker-compose up

FILES:
    Configuration: $PODMAN_CONFIG_DIR
    Storage: $PODMAN_STORAGE_DIR
    User Config: ~/.config/containers

EOF
}

# Run self-test
run_self_test() {
    print_header "Running Podman Module Self-Test"

    local tests_passed=0
    local tests_failed=0

    # Test: Check if system supports containers
    if [ -e /proc/sys/kernel/unprivileged_userns_clone ]; then
        if [ "$(cat /proc/sys/kernel/unprivileged_userns_clone)" = "1" ]; then
            ((tests_passed++))
            print_success "Unprivileged user namespaces enabled"
        else
            ((tests_failed++))
            print_warning "Unprivileged user namespaces disabled"
        fi
    fi

    # Test: Check for required kernel features
    for feature in overlay namespace cgroup; do
        if grep -q "$feature" /proc/filesystems 2>/dev/null; then
            ((tests_passed++))
            print_success "Kernel supports $feature"
        else
            ((tests_failed++))
            print_error "Kernel missing $feature support"
        fi
    done

    # Test: Check for package manager
    if command -v apt &>/dev/null || command -v dnf &>/dev/null; then
        ((tests_passed++))
        print_success "Package manager available"
    else
        ((tests_failed++))
        print_error "No supported package manager"
    fi

    # Summary
    echo ""
    echo "Test Results:"
    echo "  Passed: $tests_passed"
    echo "  Failed: $tests_failed"

    if [ $tests_failed -eq 0 ]; then
        print_success "All tests passed!"
        return 0
    else
        print_warning "Some tests failed, but module may still work"
        return 1
    fi
}

# Confirm action helper
confirm_action() {
    local prompt="${1:-Continue?}"
    read -p "$prompt [y/N]: " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Export all functions
export -f install_podman configure_podman
export -f setup_rootless_mode setup_docker_compatibility
export -f install_podman_compose create_container_service
export -f setup_auto_update create_pod deploy_pod_yaml
export -f migrate_from_docker test_podman
export -f setup_podman_complete

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
        --install)
            install_podman
            ;;
        --configure)
            configure_podman
            ;;
        --rootless)
            setup_rootless_mode
            ;;
        --docker-compat)
            setup_docker_compatibility
            ;;
        --compose)
            install_podman_compose
            ;;
        --auto-update)
            setup_auto_update
            ;;
        --migrate)
            migrate_from_docker
            ;;
        --create-service)
            create_container_service "${2:-}" "${3:-}" "${4:-}"
            ;;
        --create-pod)
            create_pod "${2:-}" "${3:-}"
            ;;
        --deploy-yaml)
            deploy_pod_yaml "${2:-}"
            ;;
        --test)
            test_podman
            ;;
        --complete)
            setup_podman_complete
            ;;
        --help)
            show_help
            ;;
        --test-module)
            run_self_test
            ;;
        *)
            echo "Podman Container Runtime Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi
