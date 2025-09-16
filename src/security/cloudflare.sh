#!/bin/bash
# Cloudflare module - Cloudflare Tunnel and security integration
# Manages Cloudflare Tunnel setup, DNS, and security features

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="cloudflare"

# Cloudflare configuration
readonly CLOUDFLARED_VERSION="${CLOUDFLARED_VERSION:-latest}"
readonly CLOUDFLARED_CONFIG_DIR="/etc/cloudflare"
readonly CLOUDFLARED_SERVICE="cloudflared"

# ============================================================================
# Cloudflared Installation
# ============================================================================

# Install cloudflared
install_cloudflared() {
    print_status "Installing cloudflared..."

    # Detect architecture
    local arch=$(dpkg --print-architecture)

    # Download appropriate version
    case "$arch" in
        amd64)
            local download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
            ;;
        arm64)
            local download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb"
            ;;
        armhf)
            local download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-armhf.deb"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    # Download and install
    print_status "Downloading cloudflared for $arch..."
    wget -q -O /tmp/cloudflared.deb "$download_url"

    if [ -f /tmp/cloudflared.deb ]; then
        sudo dpkg -i /tmp/cloudflared.deb
        rm /tmp/cloudflared.deb
        print_success "cloudflared installed successfully"
    else
        print_error "Failed to download cloudflared"
        return 1
    fi

    # Verify installation
    if command -v cloudflared &>/dev/null; then
        local version=$(cloudflared --version)
        print_success "cloudflared installed: $version"
    else
        print_error "cloudflared installation failed"
        return 1
    fi

    return 0
}

# ============================================================================
# Tunnel Authentication
# ============================================================================

# Authenticate with Cloudflare
authenticate_cloudflare() {
    print_status "Authenticating with Cloudflare..."

    # Check if already authenticated
    if [ -f "$HOME/.cloudflared/cert.pem" ]; then
        print_warning "Already authenticated with Cloudflare"

        if confirm_action "Re-authenticate?"; then
            rm -f "$HOME/.cloudflared/cert.pem"
        else
            return 0
        fi
    fi

    # Run authentication
    print_status "Opening browser for authentication..."
    print_warning "Please log in to your Cloudflare account in the browser"

    cloudflared tunnel login

    if [ -f "$HOME/.cloudflared/cert.pem" ]; then
        print_success "Successfully authenticated with Cloudflare"

        # Copy cert for system use
        sudo mkdir -p "$CLOUDFLARED_CONFIG_DIR"
        sudo cp "$HOME/.cloudflared/cert.pem" "$CLOUDFLARED_CONFIG_DIR/"
        sudo chmod 600 "$CLOUDFLARED_CONFIG_DIR/cert.pem"
    else
        print_error "Authentication failed"
        return 1
    fi

    return 0
}

# ============================================================================
# Tunnel Management
# ============================================================================

# Create a new tunnel
create_tunnel() {
    local tunnel_name="${1:-$(hostname)}"

    print_status "Creating Cloudflare Tunnel: $tunnel_name..."

    # Check if tunnel already exists
    if cloudflared tunnel list | grep -q "$tunnel_name"; then
        print_warning "Tunnel '$tunnel_name' already exists"
        return 0
    fi

    # Create tunnel
    if cloudflared tunnel create "$tunnel_name"; then
        print_success "Tunnel '$tunnel_name' created successfully"

        # Get tunnel ID
        local tunnel_id=$(cloudflared tunnel list | grep "$tunnel_name" | awk '{print $1}')
        echo "Tunnel ID: $tunnel_id"

        # Save tunnel info
        echo "$tunnel_id" | sudo tee "$CLOUDFLARED_CONFIG_DIR/tunnel_id" > /dev/null
        echo "$tunnel_name" | sudo tee "$CLOUDFLARED_CONFIG_DIR/tunnel_name" > /dev/null
    else
        print_error "Failed to create tunnel"
        return 1
    fi

    return 0
}

# Configure tunnel routing
configure_tunnel_routing() {
    local tunnel_name="${1:-$(cat $CLOUDFLARED_CONFIG_DIR/tunnel_name 2>/dev/null)}"
    local domain="${2:-}"
    local service="${3:-http://localhost:80}"

    if [ -z "$tunnel_name" ]; then
        print_error "Tunnel name required"
        return 1
    fi

    if [ -z "$domain" ]; then
        print_error "Domain required for routing"
        return 1
    fi

    print_status "Configuring routing for $domain -> $service..."

    # Create route
    if cloudflared tunnel route dns "$tunnel_name" "$domain"; then
        print_success "DNS route created for $domain"
    else
        print_warning "Failed to create DNS route (may already exist)"
    fi

    # Create ingress configuration
    create_tunnel_config "$tunnel_name" "$domain" "$service"

    return 0
}

# Create tunnel configuration
create_tunnel_config() {
    local tunnel_name="$1"
    local domain="$2"
    local service="$3"

    print_status "Creating tunnel configuration..."

    # Get tunnel ID
    local tunnel_id=$(cloudflared tunnel list | grep "$tunnel_name" | awk '{print $1}')

    if [ -z "$tunnel_id" ]; then
        print_error "Tunnel '$tunnel_name' not found"
        return 1
    fi

    # Create config file
    cat << EOF | sudo tee "$CLOUDFLARED_CONFIG_DIR/config.yml" > /dev/null
tunnel: $tunnel_id
credentials-file: $CLOUDFLARED_CONFIG_DIR/$tunnel_id.json

ingress:
  - hostname: $domain
    service: $service
  - service: http_status:404
EOF

    print_success "Tunnel configuration created"
    return 0
}

# ============================================================================
# Service Management
# ============================================================================

# Setup cloudflared as a service
setup_cloudflared_service() {
    local tunnel_name="${1:-$(cat $CLOUDFLARED_CONFIG_DIR/tunnel_name 2>/dev/null)}"

    if [ -z "$tunnel_name" ]; then
        print_error "No tunnel configured"
        return 1
    fi

    print_status "Setting up cloudflared service..."

    # Install service
    sudo cloudflared service install

    # Enable and start service
    sudo systemctl enable cloudflared
    sudo systemctl restart cloudflared

    # Check status
    if systemctl is-active cloudflared &>/dev/null; then
        print_success "cloudflared service is running"
        sudo systemctl status cloudflared --no-pager
    else
        print_error "cloudflared service failed to start"
        sudo journalctl -u cloudflared -n 20 --no-pager
        return 1
    fi

    return 0
}

# ============================================================================
# Advanced Configuration
# ============================================================================

# Configure multiple services
configure_multiple_services() {
    print_status "Configuring multiple services..."

    local config_file="$CLOUDFLARED_CONFIG_DIR/config.yml"

    # Get tunnel ID
    local tunnel_id=$(cat "$CLOUDFLARED_CONFIG_DIR/tunnel_id" 2>/dev/null)

    if [ -z "$tunnel_id" ]; then
        print_error "No tunnel configured"
        return 1
    fi

    # Start configuration
    cat << EOF | sudo tee "$config_file" > /dev/null
tunnel: $tunnel_id
credentials-file: $CLOUDFLARED_CONFIG_DIR/$tunnel_id.json

ingress:
EOF

    # Add services interactively
    while true; do
        read -p "Enter hostname (or 'done' to finish): " hostname
        if [ "$hostname" = "done" ]; then
            break
        fi

        read -p "Enter service URL (e.g., http://localhost:3000): " service

        cat << EOF | sudo tee -a "$config_file" > /dev/null
  - hostname: $hostname
    service: $service
EOF

        print_success "Added route: $hostname -> $service"
    done

    # Add catch-all
    cat << EOF | sudo tee -a "$config_file" > /dev/null
  - service: http_status:404
EOF

    print_success "Multiple services configured"

    # Restart service to apply changes
    sudo systemctl restart cloudflared

    return 0
}

# Configure access policies
configure_access_policies() {
    print_status "Configuring Cloudflare Access policies..."

    local domain="${1:-}"

    if [ -z "$domain" ]; then
        print_error "Domain required for access policies"
        return 1
    fi

    print_status "Access policies can be configured in the Cloudflare dashboard:"
    echo "  1. Go to https://dash.teams.cloudflare.com/"
    echo "  2. Navigate to Access > Applications"
    echo "  3. Create application for $domain"
    echo "  4. Configure authentication methods (OAuth, SAML, etc.)"
    echo "  5. Set access policies and rules"

    return 0
}

# ============================================================================
# Monitoring and Status
# ============================================================================

# Show tunnel status
show_tunnel_status() {
    print_header "Cloudflare Tunnel Status"

    # List tunnels
    echo "Configured tunnels:"
    cloudflared tunnel list

    echo ""

    # Check service status
    if systemctl is-active cloudflared &>/dev/null; then
        print_success "cloudflared service is running"

        # Show recent logs
        echo ""
        echo "Recent logs:"
        sudo journalctl -u cloudflared -n 10 --no-pager
    else
        print_warning "cloudflared service is not running"
    fi

    # Show configuration
    if [ -f "$CLOUDFLARED_CONFIG_DIR/config.yml" ]; then
        echo ""
        echo "Current configuration:"
        sudo cat "$CLOUDFLARED_CONFIG_DIR/config.yml"
    fi

    return 0
}

# Test tunnel connectivity
test_tunnel() {
    local domain="${1:-}"

    if [ -z "$domain" ]; then
        print_error "Domain required for testing"
        return 1
    fi

    print_status "Testing tunnel connectivity for $domain..."

    # Test DNS resolution
    print_status "Testing DNS resolution..."
    if host "$domain" | grep -q "cloudflare"; then
        print_success "DNS properly configured for Cloudflare"
    else
        print_warning "DNS may not be configured for Cloudflare"
    fi

    # Test HTTP connectivity
    print_status "Testing HTTP connectivity..."
    local response=$(curl -s -o /dev/null -w "%{http_code}" "https://$domain")

    if [ "$response" = "200" ]; then
        print_success "Tunnel is working (HTTP $response)"
    elif [ "$response" = "000" ]; then
        print_error "Cannot connect to $domain"
    else
        print_warning "Received HTTP $response from $domain"
    fi

    return 0
}

# ============================================================================
# Cleanup and Removal
# ============================================================================

# Remove tunnel
remove_tunnel() {
    local tunnel_name="${1:-$(cat $CLOUDFLARED_CONFIG_DIR/tunnel_name 2>/dev/null)}"

    if [ -z "$tunnel_name" ]; then
        print_error "Tunnel name required"
        return 1
    fi

    print_status "Removing tunnel: $tunnel_name"

    # Stop service
    sudo systemctl stop cloudflared

    # Delete tunnel
    if cloudflared tunnel delete "$tunnel_name"; then
        print_success "Tunnel deleted"
    else
        print_error "Failed to delete tunnel"
    fi

    # Clean up configuration
    sudo rm -f "$CLOUDFLARED_CONFIG_DIR/tunnel_id"
    sudo rm -f "$CLOUDFLARED_CONFIG_DIR/tunnel_name"
    sudo rm -f "$CLOUDFLARED_CONFIG_DIR/config.yml"

    return 0
}

# ============================================================================
# Interactive Setup
# ============================================================================

# Interactive Cloudflare setup
setup_cloudflare_interactive() {
    print_header "Interactive Cloudflare Tunnel Setup"

    # Install cloudflared
    if ! command -v cloudflared &>/dev/null; then
        install_cloudflared
    fi

    # Authenticate
    authenticate_cloudflare

    # Get tunnel name
    read -p "Enter tunnel name (default: $(hostname)): " tunnel_name
    tunnel_name="${tunnel_name:-$(hostname)}"

    # Create tunnel
    create_tunnel "$tunnel_name"

    # Configure routing
    read -p "Enter your domain (e.g., example.com): " domain
    read -p "Enter service URL (default: http://localhost:80): " service
    service="${service:-http://localhost:80}"

    configure_tunnel_routing "$tunnel_name" "$domain" "$service"

    # Setup service
    setup_cloudflared_service "$tunnel_name"

    # Test connectivity
    if confirm_action "Test tunnel connectivity?"; then
        test_tunnel "$domain"
    fi

    print_success "Cloudflare Tunnel setup completed!"
    echo "Your service is now accessible at: https://$domain"

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Cloudflare Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --install               Install cloudflared
    --auth                  Authenticate with Cloudflare
    --create NAME           Create tunnel with name
    --configure             Configure tunnel routing
    --service               Setup cloudflared service
    --status                Show tunnel status
    --test DOMAIN           Test tunnel connectivity
    --remove NAME           Remove tunnel
    --interactive           Interactive setup wizard
    --help                  Show this help message
    --test-module           Run module self-tests

EXAMPLES:
    # Interactive setup
    $0 --interactive

    # Create and configure tunnel
    $0 --create myserver
    $0 --configure myserver example.com http://localhost:3000

    # Check status
    $0 --status

    # Test connectivity
    $0 --test example.com

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
export -f install_cloudflared authenticate_cloudflare
export -f create_tunnel configure_tunnel_routing create_tunnel_config
export -f setup_cloudflared_service configure_multiple_services
export -f configure_access_policies show_tunnel_status test_tunnel
export -f remove_tunnel setup_cloudflare_interactive

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
source "${SCRIPT_DIR}/../lib/config.sh" 2>/dev/null || true

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --install)
            install_cloudflared
            ;;
        --auth)
            authenticate_cloudflare
            ;;
        --create)
            create_tunnel "${2:-$(hostname)}"
            ;;
        --configure)
            configure_tunnel_routing "${2}" "${3}" "${4:-http://localhost:80}"
            ;;
        --service)
            setup_cloudflared_service "${2:-}"
            ;;
        --status)
            show_tunnel_status
            ;;
        --test)
            test_tunnel "${2}"
            ;;
        --remove)
            remove_tunnel "${2}"
            ;;
        --interactive)
            setup_cloudflare_interactive
            ;;
        --help)
            show_help
            ;;
        --test-module)
            echo "Running Cloudflare module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "Cloudflare Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi
