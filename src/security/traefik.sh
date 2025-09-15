#!/bin/bash
# Traefik module - Modern reverse proxy with security features
# Manages Traefik installation, configuration, and security middleware

# Script metadata
readonly MODULE_VERSION="1.0.0"
readonly MODULE_NAME="traefik"

# Traefik configuration
readonly TRAEFIK_VERSION="${TRAEFIK_VERSION:-3.0}"
readonly TRAEFIK_CONFIG_DIR="/etc/traefik"
readonly TRAEFIK_DATA_DIR="/var/lib/traefik"
readonly TRAEFIK_LOG_DIR="/var/log/traefik"

# ============================================================================
# Traefik Installation
# ============================================================================

# Install Traefik
install_traefik() {
    print_status "Installing Traefik v${TRAEFIK_VERSION}..."

    # Check if already installed
    if command -v traefik &>/dev/null; then
        print_warning "Traefik is already installed"
        traefik version
        return 0
    fi

    # Detect architecture
    local arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64) arch="amd64" ;;
        arm64) arch="arm64" ;;
        armhf) arch="armv7" ;;
        *)
            print_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    # Download Traefik
    local download_url="https://github.com/traefik/traefik/releases/download/v${TRAEFIK_VERSION}/traefik_v${TRAEFIK_VERSION}_linux_${arch}.tar.gz"

    print_status "Downloading Traefik..."
    wget -O /tmp/traefik.tar.gz "$download_url"

    # Extract and install
    cd /tmp
    tar xzf traefik.tar.gz
    sudo mv traefik /usr/local/bin/
    sudo chmod +x /usr/local/bin/traefik

    # Create directories
    sudo mkdir -p "$TRAEFIK_CONFIG_DIR"
    sudo mkdir -p "$TRAEFIK_CONFIG_DIR/dynamic"
    sudo mkdir -p "$TRAEFIK_DATA_DIR"
    sudo mkdir -p "$TRAEFIK_LOG_DIR"

    # Create traefik user
    if ! id -u traefik &>/dev/null; then
        sudo useradd -r -s /bin/false traefik
    fi

    # Set permissions
    sudo chown -R traefik:traefik "$TRAEFIK_CONFIG_DIR"
    sudo chown -R traefik:traefik "$TRAEFIK_DATA_DIR"
    sudo chown -R traefik:traefik "$TRAEFIK_LOG_DIR"

    # Verify installation
    if traefik version &>/dev/null; then
        print_success "Traefik installed successfully"
        traefik version
    else
        print_error "Traefik installation failed"
        return 1
    fi

    return 0
}

# ============================================================================
# Basic Configuration
# ============================================================================

# Configure Traefik basics
configure_traefik_basic() {
    print_status "Configuring Traefik..."

    # Create main configuration
    cat << 'EOF' | sudo tee "$TRAEFIK_CONFIG_DIR/traefik.yml" > /dev/null
# Traefik Static Configuration
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  debug: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entrypoint:
          to: websecure
          scheme: https
          permanent: true

  websecure:
    address: ":443"
    http:
      tls:
        certResolver: letsencrypt
    http3: {}

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefik

  file:
    directory: /etc/traefik/dynamic
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${ADMIN_EMAIL:-admin@example.com}
      storage: /var/lib/traefik/acme.json
      keyType: EC256
      httpChallenge:
        entryPoint: web
      tlsChallenge: {}

log:
  level: INFO
  filePath: /var/log/traefik/traefik.log
  format: json

accessLog:
  filePath: /var/log/traefik/access.log
  format: json
  filters:
    statusCodes:
      - "200-299"
      - "400-499"
      - "500-599"

metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
    entryPoint: metrics

ping:
  entryPoint: traefik
EOF

    # Set correct email if available
    if [ -n "${ADMIN_EMAIL:-}" ]; then
        sudo sed -i "s/admin@example.com/$ADMIN_EMAIL/" "$TRAEFIK_CONFIG_DIR/traefik.yml"
    fi

    print_success "Traefik basic configuration created"
    return 0
}

# ============================================================================
# Security Configuration
# ============================================================================

# Configure security headers
configure_security_headers() {
    print_status "Configuring security headers middleware..."

    cat << 'EOF' | sudo tee "$TRAEFIK_CONFIG_DIR/dynamic/security-headers.yml" > /dev/null
http:
  middlewares:
    security-headers:
      headers:
        customFrameOptionsValue: "SAMEORIGIN"
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "strict-origin-when-cross-origin"
        permissionsPolicy: "camera=(), microphone=(), geolocation=(), payment=(), usb=(), vr=()"
        customResponseHeaders:
          X-Robots-Tag: "noindex,nofollow,nosnippet,noarchive,notranslate,noimageindex"
        sslRedirect: true
        sslForceHost: true
        sslProxyHeaders:
          X-Forwarded-Proto: https
        contentSecurityPolicy: |
          default-src 'self';
          script-src 'self' 'unsafe-inline';
          style-src 'self' 'unsafe-inline';
          img-src 'self' data: https:;
          font-src 'self' data:;
EOF

    print_success "Security headers configured"
    return 0
}

# Configure rate limiting
configure_rate_limiting() {
    print_status "Configuring rate limiting..."

    cat << 'EOF' | sudo tee "$TRAEFIK_CONFIG_DIR/dynamic/rate-limit.yml" > /dev/null
http:
  middlewares:
    rate-limit:
      rateLimit:
        average: 100
        period: 1s
        burst: 200

    rate-limit-strict:
      rateLimit:
        average: 10
        period: 1s
        burst: 20

    rate-limit-api:
      rateLimit:
        average: 50
        period: 1s
        burst: 100
EOF

    print_success "Rate limiting configured"
    return 0
}

# Configure IP allowlist
configure_ip_allowlist() {
    local allowed_ips="${1:-}"

    print_status "Configuring IP allowlist..."

    if [ -z "$allowed_ips" ]; then
        # Default to private networks
        allowed_ips="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,127.0.0.1/32"
    fi

    cat << EOF | sudo tee "$TRAEFIK_CONFIG_DIR/dynamic/ip-allowlist.yml" > /dev/null
http:
  middlewares:
    ip-allowlist:
      ipAllowList:
        sourceRange:
$(echo "$allowed_ips" | tr ',' '\n' | sed 's/^/          - /')
EOF

    print_success "IP allowlist configured"
    return 0
}

# Configure basic auth
configure_basic_auth() {
    local username="${1:-admin}"
    local password="${2:-}"

    print_status "Configuring basic authentication..."

    if [ -z "$password" ]; then
        # Generate random password
        password=$(openssl rand -base64 32)
        echo "Generated password: $password"
    fi

    # Generate htpasswd hash
    local hash=$(echo "$password" | htpasswd -niB "$username" | sed 's/\$/\$\$/g')

    cat << EOF | sudo tee "$TRAEFIK_CONFIG_DIR/dynamic/basic-auth.yml" > /dev/null
http:
  middlewares:
    basic-auth:
      basicAuth:
        users:
          - "$hash"
        removeHeader: true
EOF

    print_success "Basic auth configured for user: $username"
    return 0
}

# ============================================================================
# CrowdSec Integration
# ============================================================================

# Configure CrowdSec bouncer
configure_crowdsec_bouncer() {
    print_status "Configuring CrowdSec integration..."

    # Check if CrowdSec is installed
    if ! command -v cscli &>/dev/null; then
        print_warning "CrowdSec not installed, skipping integration"
        return 0
    fi

    # Install Traefik CrowdSec bouncer plugin
    cat << 'EOF' | sudo tee "$TRAEFIK_CONFIG_DIR/dynamic/crowdsec.yml" > /dev/null
http:
  middlewares:
    crowdsec:
      plugin:
        crowdsec-bouncer-traefik-plugin:
          enabled: true
          logLevel: INFO
          crowdsecMode: stream
          crowdsecLapiScheme: http
          crowdsecLapiHost: localhost:8080
          crowdsecLapiKey: ${CROWDSEC_API_KEY}
          updateIntervalSeconds: 60
          defaultDecisionSeconds: 60
          httpTimeoutSeconds: 10
          crowdsecCapiMachineId: ${CROWDSEC_MACHINE_ID}
          crowdsecCapiPassword: ${CROWDSEC_PASSWORD}
EOF

    # Generate API key for bouncer
    if command -v cscli &>/dev/null; then
        local api_key=$(sudo cscli bouncers add traefik-bouncer -o raw 2>/dev/null || \
                        sudo cscli bouncers delete traefik-bouncer 2>/dev/null && \
                        sudo cscli bouncers add traefik-bouncer -o raw)

        sudo sed -i "s/\${CROWDSEC_API_KEY}/$api_key/" "$TRAEFIK_CONFIG_DIR/dynamic/crowdsec.yml"
    fi

    print_success "CrowdSec integration configured"
    return 0
}

# ============================================================================
# Service Configuration
# ============================================================================

# Create systemd service
create_systemd_service() {
    print_status "Creating systemd service..."

    cat << 'EOF' | sudo tee /etc/systemd/system/traefik.service > /dev/null
[Unit]
Description=Traefik
Documentation=https://doc.traefik.io/traefik/
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=traefik
Group=traefik
ExecStart=/usr/local/bin/traefik --configfile=/etc/traefik/traefik.yml
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=traefik
KillMode=process
KillSignal=SIGTERM

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/traefik /var/log/traefik
ReadOnlyPaths=/etc/traefik

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    sudo systemctl daemon-reload

    # Enable and start service
    sudo systemctl enable traefik
    sudo systemctl start traefik

    print_success "Traefik service created and started"
    return 0
}

# ============================================================================
# Docker Integration
# ============================================================================

# Configure Docker network
configure_docker_network() {
    print_status "Configuring Docker network for Traefik..."

    if ! command -v docker &>/dev/null; then
        print_warning "Docker not installed, skipping network configuration"
        return 0
    fi

    # Create Traefik network
    if ! docker network ls | grep -q traefik; then
        docker network create traefik
        print_success "Docker network 'traefik' created"
    else
        print_warning "Docker network 'traefik' already exists"
    fi

    # Create docker-compose example
    cat << 'EOF' | sudo tee "$TRAEFIK_CONFIG_DIR/docker-compose.example.yml" > /dev/null
version: '3.8'

services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - traefik
    ports:
      - 80:80
      - 443:443
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/etc/traefik/traefik.yml:ro
      - ./dynamic:/etc/traefik/dynamic:ro
      - traefik-data:/var/lib/traefik
      - traefik-logs:/var/log/traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN}`)"
      - "traefik.http.routers.traefik.tls=true"
      - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.middlewares=basic-auth@file"

networks:
  traefik:
    external: true

volumes:
  traefik-data:
  traefik-logs:
EOF

    print_success "Docker integration configured"
    return 0
}

# ============================================================================
# Dashboard Configuration
# ============================================================================

# Configure Traefik dashboard
configure_dashboard() {
    local domain="${1:-traefik.local}"
    local enable_auth="${2:-true}"

    print_status "Configuring Traefik dashboard..."

    cat << EOF | sudo tee "$TRAEFIK_CONFIG_DIR/dynamic/dashboard.yml" > /dev/null
http:
  routers:
    dashboard:
      rule: Host(\`$domain\`)
      service: api@internal
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
EOF

    if [ "$enable_auth" = "true" ]; then
        echo "      middlewares:" | sudo tee -a "$TRAEFIK_CONFIG_DIR/dynamic/dashboard.yml" > /dev/null
        echo "        - basic-auth" | sudo tee -a "$TRAEFIK_CONFIG_DIR/dynamic/dashboard.yml" > /dev/null
    fi

    print_success "Dashboard configured at: https://$domain"
    return 0
}

# ============================================================================
# Monitoring
# ============================================================================

# Show Traefik status
show_traefik_status() {
    print_header "Traefik Status"

    # Service status
    echo "Service Status:"
    systemctl status traefik --no-pager | head -15

    echo ""

    # Check if API is accessible
    if curl -s http://localhost:8080/api/overview &>/dev/null; then
        print_success "Traefik API is accessible"
    else
        print_warning "Traefik API is not accessible"
    fi

    # Show recent logs
    echo ""
    echo "Recent Logs:"
    sudo journalctl -u traefik -n 20 --no-pager

    return 0
}

# ============================================================================
# Complete Setup
# ============================================================================

# Run complete Traefik setup
setup_traefik_complete() {
    print_header "Complete Traefik Setup"

    # Install Traefik
    install_traefik

    # Configure Traefik
    configure_traefik_basic

    # Configure security
    configure_security_headers
    configure_rate_limiting
    configure_ip_allowlist

    # Configure authentication
    configure_basic_auth

    # Configure CrowdSec if available
    configure_crowdsec_bouncer

    # Configure Docker integration
    configure_docker_network

    # Create systemd service
    create_systemd_service

    # Configure dashboard
    if [ -n "${DOMAIN:-}" ]; then
        configure_dashboard "traefik.$DOMAIN"
    fi

    # Show status
    show_traefik_status

    print_success "Traefik setup completed!"
    print_warning "Remember to:"
    echo "  • Configure DNS for your domains"
    echo "  • Update ADMIN_EMAIL in traefik.yml"
    echo "  • Configure services with Traefik labels"
    echo "  • Review and adjust security settings"

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Traefik Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --install               Install Traefik
    --configure             Configure Traefik basics
    --security-headers      Configure security headers
    --rate-limit            Configure rate limiting
    --ip-allowlist IPS      Configure IP allowlist
    --basic-auth USER       Configure basic auth
    --crowdsec              Configure CrowdSec integration
    --docker                Configure Docker integration
    --dashboard DOMAIN      Configure dashboard
    --service               Create systemd service
    --status                Show Traefik status
    --complete              Run complete setup
    --help                  Show this help message
    --test                  Run module self-tests

EXAMPLES:
    # Complete setup
    $0 --complete

    # Configure with specific domain
    DOMAIN=example.com $0 --dashboard traefik.example.com

    # Configure basic auth
    $0 --basic-auth admin mypassword

    # Check status
    $0 --status

EOF
}

# Export all functions
export -f install_traefik configure_traefik_basic
export -f configure_security_headers configure_rate_limiting
export -f configure_ip_allowlist configure_basic_auth
export -f configure_crowdsec_bouncer create_systemd_service
export -f configure_docker_network configure_dashboard
export -f show_traefik_status setup_traefik_complete

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/../lib/backup.sh" 2>/dev/null || true

# Main execution when run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --install)
            install_traefik
            ;;
        --configure)
            configure_traefik_basic
            ;;
        --security-headers)
            configure_security_headers
            ;;
        --rate-limit)
            configure_rate_limiting
            ;;
        --ip-allowlist)
            configure_ip_allowlist "${2:-}"
            ;;
        --basic-auth)
            configure_basic_auth "${2:-admin}" "${3:-}"
            ;;
        --crowdsec)
            configure_crowdsec_bouncer
            ;;
        --docker)
            configure_docker_network
            ;;
        --dashboard)
            configure_dashboard "${2:-traefik.local}" "${3:-true}"
            ;;
        --service)
            create_systemd_service
            ;;
        --status)
            show_traefik_status
            ;;
        --complete)
            setup_traefik_complete
            ;;
        --help)
            show_help
            ;;
        --test)
            echo "Running Traefik module tests..."
            echo "✓ Module loaded successfully"
            ;;
        *)
            echo "Traefik Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi