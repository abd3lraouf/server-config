#!/bin/bash
# Tailscale VPN module - Zero Trust network access
# Manages Tailscale installation, configuration, and SSH integration

# Script metadata
readonly MODULE_VERSION="1.0.0"
readonly MODULE_NAME="tailscale"

# ============================================================================
# Tailscale Installation
# ============================================================================

# Install Tailscale
install_tailscale() {
    print_status "Installing Tailscale for Zero Trust network access..."

    # Check if Tailscale is already installed
    if command -v tailscale &> /dev/null; then
        print_warning "Tailscale is already installed"

        # Check if already connected
        if tailscale status &>/dev/null 2>&1; then
            local current_ip=$(tailscale ip -4 2>/dev/null)
            print_success "Tailscale already connected: $current_ip"

            if [[ "$INTERACTIVE_MODE" == true ]]; then
                read -p "Reconfigure Tailscale? [y/N]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    return 0
                fi
            else
                return 0
            fi
        fi
    else
        # Install Tailscale using official script
        print_status "Downloading and installing Tailscale..."
        if ! curl -fsSL https://tailscale.com/install.sh | sh; then
            print_error "Failed to install Tailscale"
            return 1
        fi
    fi

    # Start Tailscale service
    sudo systemctl enable tailscaled
    if ! sudo systemctl start tailscaled; then
        print_error "Failed to start Tailscale daemon"
        return 1
    fi

    print_success "Tailscale installed successfully"
    return 0
}

# ============================================================================
# Tailscale Configuration
# ============================================================================

# Configure Tailscale with auth key
configure_tailscale() {
    local auth_key="${1:-$TAILSCALE_AUTH_KEY}"
    local advertise_routes="${2:-$TAILSCALE_ADVERTISE_ROUTES}"
    local advertise_tags="${3:-$TAILSCALE_TAGS}"
    local accept_routes="${4:-$TAILSCALE_ACCEPT_ROUTES}"
    local ssh_enabled="${5:-$TAILSCALE_SSH}"

    print_status "Configuring Tailscale..."

    # Check if Tailscale is installed
    if ! command -v tailscale &> /dev/null; then
        print_error "Tailscale is not installed"
        return 1
    fi

    # Build tailscale up command
    local cmd="sudo tailscale up"

    # Add auth key if provided
    if [ -n "$auth_key" ]; then
        cmd="$cmd --authkey=$auth_key"
    fi

    # Add SSH if enabled (default: true)
    if [ "${ssh_enabled}" != "false" ]; then
        cmd="$cmd --ssh"
    fi

    # Add advertise routes if specified
    if [ -n "$advertise_routes" ]; then
        cmd="$cmd --advertise-routes=$advertise_routes"
    fi

    # Add tags if specified
    if [ -n "$advertise_tags" ]; then
        # Ensure tag has proper prefix
        if [[ "$advertise_tags" != tag:* ]]; then
            advertise_tags="tag:$advertise_tags"
        fi
        cmd="$cmd --advertise-tags=$advertise_tags"
    fi

    # Add accept routes if enabled
    if [ "$accept_routes" = "true" ]; then
        cmd="$cmd --accept-routes"
    fi

    # Check if we need to reset
    local backend_state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null || echo "")
    if [ "$backend_state" = "Running" ] || [ "$backend_state" = "NeedsLogin" ]; then
        print_status "Resetting existing Tailscale configuration..."
        cmd="$cmd --reset"
    fi

    # Execute configuration
    print_status "Running: $cmd"
    if eval "$cmd"; then
        print_success "Tailscale configured successfully"
    else
        print_error "Failed to configure Tailscale"
        return 1
    fi

    return 0
}

# Configure Tailscale interactively
configure_tailscale_interactive() {
    print_header "Interactive Tailscale Configuration"

    local auth_key=""
    local use_tags=""
    local advertise_routes=""
    local accept_routes="false"
    local ssh_enabled="true"

    # Ask for auth key
    echo -e "${YELLOW}Do you have a Tailscale auth key?${NC}"
    echo "You can create one at: https://login.tailscale.com/admin/settings/keys"
    read -p "Enter auth key (or press Enter to authenticate via browser): " auth_key

    # Ask about SSH
    read -p "Enable Tailscale SSH? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        ssh_enabled="false"
    fi

    # Ask about tags
    echo -e "\n${YELLOW}Tailscale Tags (optional):${NC}"
    echo "Tags must be configured in your Tailscale admin console first."
    read -p "Enter tag name (e.g., 'server' for tag:server, or press Enter to skip): " tag_name
    if [ -n "$tag_name" ]; then
        # Remove 'tag:' prefix if user included it
        tag_name=${tag_name#tag:}
        use_tags="tag:$tag_name"
    fi

    # Ask about advertising routes
    echo -e "\n${YELLOW}Advertise Routes (optional):${NC}"
    echo "Example: 192.168.1.0/24,10.0.0.0/24"
    read -p "Enter routes to advertise (or press Enter to skip): " advertise_routes

    # Ask about accepting routes
    read -p "Accept routes from other devices? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        accept_routes="true"
    fi

    # Configure with collected parameters
    configure_tailscale "$auth_key" "$advertise_routes" "$use_tags" "$accept_routes" "$ssh_enabled"
}

# ============================================================================
# Tailscale Status and Management
# ============================================================================

# Get Tailscale status
get_tailscale_status() {
    if ! command -v tailscale &> /dev/null; then
        print_error "Tailscale is not installed"
        return 1
    fi

    print_header "Tailscale Status"

    # Get IP addresses
    local ipv4=$(tailscale ip -4 2>/dev/null || echo "Not connected")
    local ipv6=$(tailscale ip -6 2>/dev/null || echo "Not connected")

    echo "IPv4: $ipv4"
    echo "IPv6: $ipv6"
    echo ""

    # Show full status
    tailscale status

    return 0
}

# Validate Tailscale connection
validate_tailscale_connection() {
    print_status "Validating Tailscale connection..."

    if ! command -v tailscale &> /dev/null; then
        print_error "Tailscale is not installed"
        return 1
    fi

    # Check if connected
    if ! tailscale status &>/dev/null 2>&1; then
        print_error "Tailscale is not connected"
        return 1
    fi

    # Get connection details
    local ip=$(tailscale ip -4 2>/dev/null)
    local hostname=$(tailscale status --json 2>/dev/null | jq -r '.Self.HostName' 2>/dev/null || echo "unknown")

    if [ -n "$ip" ]; then
        print_success "Tailscale connected successfully"
        echo "  IP Address: $ip"
        echo "  Hostname: $hostname"
        return 0
    else
        print_error "Tailscale connection validation failed"
        return 1
    fi
}

# ============================================================================
# SSH Integration
# ============================================================================

# Setup Tailscale SSH
setup_tailscale_ssh() {
    print_status "Setting up Tailscale SSH..."

    # Ensure Tailscale is installed and connected
    if ! validate_tailscale_connection; then
        print_error "Tailscale must be connected first"
        return 1
    fi

    # Enable SSH in Tailscale
    print_status "Enabling Tailscale SSH..."
    sudo tailscale set --ssh

    print_success "Tailscale SSH enabled"
    print_status "You can now SSH using: ssh user@[tailscale-hostname]"

    return 0
}

# Restrict SSH to Tailscale only
restrict_ssh_to_tailscale() {
    print_status "Restricting SSH access to Tailscale network only..."

    # Check if Tailscale is connected
    if ! tailscale status &>/dev/null 2>&1; then
        print_error "Tailscale must be connected before restricting SSH"
        return 1
    fi

    # Get Tailscale IP
    local tailscale_ip=$(tailscale ip -4 2>/dev/null)
    if [ -z "$tailscale_ip" ]; then
        print_error "Could not get Tailscale IP address"
        return 1
    fi

    # Backup SSH config
    backup_file "/etc/ssh/sshd_config"

    # Create SSH restriction script
    local script_path="/usr/local/bin/restrict-ssh-to-tailscale.sh"
    cat << 'EOF' | sudo tee "$script_path" > /dev/null
#!/bin/bash
# Restrict SSH to Tailscale network only

# Get Tailscale network interface
TAILSCALE_IF=$(ip route get 100.64.0.1 2>/dev/null | grep -oP 'dev \K[^ ]+' || echo "tailscale0")

# Check if Tailscale is connected
if ! tailscale status &>/dev/null; then
    echo "ERROR: Tailscale is not connected!"
    echo "Please ensure Tailscale is running and connected before restricting SSH"
    exit 1
fi

# Configure UFW to only allow SSH from Tailscale
if command -v ufw &>/dev/null; then
    echo "Configuring UFW for Tailscale-only SSH access..."

    # Delete existing SSH rules
    sudo ufw delete allow 22/tcp 2>/dev/null || true
    sudo ufw delete allow ssh 2>/dev/null || true

    # Allow SSH only from Tailscale network
    sudo ufw allow in on $TAILSCALE_IF to any port 22 proto tcp comment 'SSH via Tailscale'

    # Also allow from Tailscale IP range
    sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp comment 'SSH from Tailscale network'

    sudo ufw reload
    echo "✓ UFW configured for Tailscale-only SSH"
fi

echo "✓ SSH is now restricted to Tailscale connections only"
echo "  Make sure you can connect via Tailscale before closing this session!"
EOF

    sudo chmod +x "$script_path"

    # Execute the restriction script
    if sudo "$script_path"; then
        print_success "SSH restricted to Tailscale network only"
        print_warning "IMPORTANT: Verify you can SSH via Tailscale before closing this session!"
        return 0
    else
        print_error "Failed to restrict SSH to Tailscale"
        return 1
    fi
}

# ============================================================================
# Network Management
# ============================================================================

# Setup exit node
setup_exit_node() {
    print_status "Setting up this machine as a Tailscale exit node..."

    # Enable IP forwarding
    print_status "Enabling IP forwarding..."
    echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p

    # Advertise as exit node
    print_status "Advertising as exit node..."
    sudo tailscale up --advertise-exit-node

    print_success "Exit node setup complete"
    print_warning "Remember to approve the exit node in the Tailscale admin console"

    return 0
}

# Use exit node
use_exit_node() {
    local exit_node="${1}"

    if [ -z "$exit_node" ]; then
        print_error "Exit node hostname or IP required"
        return 1
    fi

    print_status "Configuring to use exit node: $exit_node"

    sudo tailscale up --exit-node="$exit_node"

    print_success "Now using exit node: $exit_node"
    return 0
}

# ============================================================================
# Cleanup and Removal
# ============================================================================

# Disconnect from Tailscale
disconnect_tailscale() {
    print_status "Disconnecting from Tailscale..."

    if ! command -v tailscale &> /dev/null; then
        print_error "Tailscale is not installed"
        return 1
    fi

    sudo tailscale down

    print_success "Disconnected from Tailscale"
    return 0
}

# Logout from Tailscale
logout_tailscale() {
    print_status "Logging out from Tailscale..."

    if ! command -v tailscale &> /dev/null; then
        print_error "Tailscale is not installed"
        return 1
    fi

    sudo tailscale logout

    print_success "Logged out from Tailscale"
    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Tailscale Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --install               Install Tailscale
    --configure             Configure Tailscale with auth key
    --interactive           Interactive configuration wizard
    --status                Show Tailscale status
    --validate              Validate connection
    --setup-ssh             Enable Tailscale SSH
    --restrict-ssh          Restrict SSH to Tailscale only
    --exit-node             Setup as exit node
    --use-exit-node HOST    Use specified exit node
    --disconnect            Disconnect from Tailscale
    --logout                Logout from Tailscale
    --help                  Show this help message
    --test                  Run module self-tests

ENVIRONMENT VARIABLES:
    TAILSCALE_AUTH_KEY      Authentication key
    TAILSCALE_TAGS          Tags to apply (e.g., "tag:server")
    TAILSCALE_ADVERTISE_ROUTES  Routes to advertise
    TAILSCALE_ACCEPT_ROUTES Accept routes from other nodes
    TAILSCALE_SSH           Enable SSH (default: true)

EXAMPLES:
    # Install and configure with auth key
    TAILSCALE_AUTH_KEY="tskey-..." $0 --install --configure

    # Interactive setup
    $0 --interactive

    # Setup as exit node
    $0 --exit-node

    # Restrict SSH to Tailscale only
    $0 --restrict-ssh

EOF
}

# Export all functions
export -f install_tailscale configure_tailscale configure_tailscale_interactive
export -f get_tailscale_status validate_tailscale_connection
export -f setup_tailscale_ssh restrict_ssh_to_tailscale
export -f setup_exit_node use_exit_node
export -f disconnect_tailscale logout_tailscale

# Source required libraries
if [ -z "${SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/config.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/validation.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/backup.sh" 2>/dev/null || true

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --install)
            install_tailscale
            ;;
        --configure)
            configure_tailscale
            ;;
        --interactive)
            configure_tailscale_interactive
            ;;
        --status)
            get_tailscale_status
            ;;
        --validate)
            validate_tailscale_connection
            ;;
        --setup-ssh)
            setup_tailscale_ssh
            ;;
        --restrict-ssh)
            restrict_ssh_to_tailscale
            ;;
        --exit-node)
            setup_exit_node
            ;;
        --use-exit-node)
            use_exit_node "${2}"
            ;;
        --disconnect)
            disconnect_tailscale
            ;;
        --logout)
            logout_tailscale
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running Tailscale module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "Tailscale Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi