#!/bin/bash
# Auto-Documentation Generator module - Comprehensive system documentation
# Generates markdown, HTML, and PDF documentation for the entire system

# Script metadata
[[ -z "${MODULE_VERSION:-}" ]] && readonly MODULE_VERSION="1.0.0"
[[ -z "${MODULE_NAME:-}" ]] && readonly MODULE_NAME="documentation-generator"

# Configuration
readonly DOC_DIR="/var/lib/server-docs"
readonly DOC_OUTPUT_DIR="$DOC_DIR/output"
readonly DOC_TEMPLATES_DIR="$DOC_DIR/templates"
readonly DOC_ASSETS_DIR="$DOC_DIR/assets"

# Documentation formats
readonly FORMATS=("markdown" "html" "pdf" "json")
readonly DEFAULT_FORMAT="markdown"

# ============================================================================
# Setup and Installation
# ============================================================================

# Setup documentation directories
setup_directories() {
    print_status "Setting up documentation directories..."

    # Create directories
    sudo mkdir -p "$DOC_DIR"
    sudo mkdir -p "$DOC_OUTPUT_DIR"
    sudo mkdir -p "$DOC_TEMPLATES_DIR"
    sudo mkdir -p "$DOC_ASSETS_DIR"
    sudo mkdir -p "$DOC_OUTPUT_DIR/markdown"
    sudo mkdir -p "$DOC_OUTPUT_DIR/html"
    sudo mkdir -p "$DOC_OUTPUT_DIR/pdf"
    sudo mkdir -p "$DOC_OUTPUT_DIR/json"

    # Set permissions
    sudo chmod 755 "$DOC_DIR"
    sudo chmod 755 "$DOC_OUTPUT_DIR"

    print_success "Documentation directories created"
    return 0
}

# Install documentation tools
install_doc_tools() {
    print_header "Installing Documentation Tools"

    print_status "Installing required packages..."

    # Install pandoc for document conversion
    if ! command -v pandoc &>/dev/null; then
        sudo apt update
        sudo apt install -y pandoc
    fi

    # Install wkhtmltopdf for PDF generation
    if ! command -v wkhtmltopdf &>/dev/null; then
        sudo apt install -y wkhtmltopdf
    fi

    # Install graphviz for diagrams
    if ! command -v dot &>/dev/null; then
        sudo apt install -y graphviz
    fi

    # Install jq for JSON processing
    if ! command -v jq &>/dev/null; then
        sudo apt install -y jq
    fi

    # Install Python packages for advanced documentation
    sudo pip3 install --quiet \
        mkdocs \
        mkdocs-material \
        markdown \
        pygments \
        pyyaml

    print_success "Documentation tools installed"
    return 0
}

# ============================================================================
# System Information Gathering
# ============================================================================

# Gather system information
gather_system_info() {
    local output_file="${1:-$DOC_OUTPUT_DIR/json/system-info.json}"

    print_status "Gathering system information..."

    # Create JSON structure
    cat << EOF > "$output_file"
{
    "generated": "$(date -Iseconds)",
    "hostname": "$(hostname -f)",
    "system": {
        "os": "$(lsb_release -ds 2>/dev/null || echo 'Unknown')",
        "kernel": "$(uname -r)",
        "architecture": "$(uname -m)",
        "uptime": "$(uptime -p)",
        "timezone": "$(timedatectl show --property=Timezone --value 2>/dev/null || echo 'UTC')"
    },
    "hardware": {
        "cpu": {
            "model": "$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)",
            "cores": $(nproc),
            "threads": $(grep -c processor /proc/cpuinfo)
        },
        "memory": {
            "total": "$(free -h | awk '/^Mem:/{print $2}')",
            "used": "$(free -h | awk '/^Mem:/{print $3}')",
            "available": "$(free -h | awk '/^Mem:/{print $7}')"
        },
        "disk": $(df -h / | tail -1 | awk '{printf "{\"size\":\"%s\",\"used\":\"%s\",\"available\":\"%s\",\"usage\":\"%s\"}", $2, $3, $4, $5}')
    },
    "network": {
        "interfaces": [
$(ip -j addr show 2>/dev/null | jq -r '.[] | "            {\"name\": \"\(.ifname)\", \"state\": \"\(.operstate)\", \"addresses\": \(.addr_info | map(.local) | @json)}"' | paste -sd,)
        ],
        "hostname": "$(hostname)",
        "domain": "$(hostname -d)",
        "dns": $(cat /etc/resolv.conf | grep nameserver | awk '{print $2}' | jq -R . | jq -s .)
    },
    "services": {
        "active": $(systemctl list-units --type=service --state=active --no-pager --no-legend | wc -l),
        "failed": $(systemctl list-units --type=service --state=failed --no-pager --no-legend | wc -l),
        "critical": [
$(for service in sshd ufw docker podman nginx apache2 mysql postgresql; do
    if systemctl is-active $service &>/dev/null; then
        echo "            \"$service\""
    fi
done | paste -sd,)
        ]
    }
}
EOF

    print_success "System information gathered"
    return 0
}

# ============================================================================
# Module Documentation
# ============================================================================

# Document all modules
document_modules() {
    local output_file="${1:-$DOC_OUTPUT_DIR/markdown/modules.md}"

    print_status "Documenting modules..."

    cat << 'EOF' > "$output_file"
# Module Documentation

## Overview

This system uses a modular architecture with self-contained, reusable components.

## Module Structure

```
src/
├── lib/          # Core libraries
├── base/         # Base system modules
├── security/     # Security modules
├── containers/   # Container runtime modules
├── monitoring/   # Monitoring and compliance
├── menu/         # Menu interfaces
└── scripts/      # Orchestration scripts
```

## Modules

EOF

    # Document each module
    for module in $(find /home/ubuntu/server-config/src -name "*.sh" -type f | sort); do
        local module_name=$(basename "$module")
        local module_dir=$(dirname "$module" | xargs basename)

        echo "### $module_dir/$module_name" >> "$output_file"
        echo "" >> "$output_file"

        # Extract description from module
        local description=$(grep "^# " "$module" | head -2 | tail -1 | sed 's/^# //')
        echo "$description" >> "$output_file"
        echo "" >> "$output_file"

        # Extract functions
        echo "**Functions:**" >> "$output_file"
        echo '```' >> "$output_file"
        grep "^[a-z_]*() {" "$module" | sed 's/() {//' | sed 's/^/- /' >> "$output_file"
        echo '```' >> "$output_file"
        echo "" >> "$output_file"

        # Module stats
        local line_count=$(wc -l < "$module")
        local function_count=$(grep -c "^[a-z_]*() {" "$module")
        echo "**Statistics:**" >> "$output_file"
        echo "- Lines: $line_count" >> "$output_file"
        echo "- Functions: $function_count" >> "$output_file"
        echo "" >> "$output_file"
        echo "---" >> "$output_file"
        echo "" >> "$output_file"
    done

    print_success "Module documentation generated"
    return 0
}

# ============================================================================
# Security Documentation
# ============================================================================

# Document security configuration
document_security() {
    local output_file="${1:-$DOC_OUTPUT_DIR/markdown/security.md}"

    print_status "Documenting security configuration..."

    cat << 'EOF' > "$output_file"
# Security Configuration Documentation

## Overview

This document details the security configuration and hardening measures implemented on this system.

## Security Layers

### 1. Network Security

EOF

    # Document firewall rules
    echo "#### Firewall Configuration" >> "$output_file"
    echo '```' >> "$output_file"
    sudo ufw status verbose >> "$output_file" 2>/dev/null || echo "Firewall not configured" >> "$output_file"
    echo '```' >> "$output_file"
    echo "" >> "$output_file"

    # Document SSH configuration
    echo "### 2. SSH Security" >> "$output_file"
    echo "" >> "$output_file"
    echo "#### SSH Configuration" >> "$output_file"
    echo '```' >> "$output_file"
    grep -E "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|Port)" /etc/ssh/sshd_config 2>/dev/null | head -10 >> "$output_file"
    echo '```' >> "$output_file"
    echo "" >> "$output_file"

    # Document fail2ban jails
    if command -v fail2ban-client &>/dev/null; then
        echo "### 3. Intrusion Prevention (Fail2ban)" >> "$output_file"
        echo "" >> "$output_file"
        echo "#### Active Jails" >> "$output_file"
        echo '```' >> "$output_file"
        sudo fail2ban-client status 2>/dev/null >> "$output_file"
        echo '```' >> "$output_file"
        echo "" >> "$output_file"
    fi

    # Document CrowdSec if installed
    if command -v cscli &>/dev/null; then
        echo "### 4. CrowdSec IPS" >> "$output_file"
        echo "" >> "$output_file"
        echo "#### Bouncers" >> "$output_file"
        echo '```' >> "$output_file"
        sudo cscli bouncers list 2>/dev/null >> "$output_file"
        echo '```' >> "$output_file"
        echo "" >> "$output_file"
    fi

    # Document system hardening
    echo "### 5. System Hardening" >> "$output_file"
    echo "" >> "$output_file"
    echo "#### Kernel Parameters" >> "$output_file"
    echo '```' >> "$output_file"
    sysctl -a 2>/dev/null | grep -E "(tcp_syncookies|ip_forward|randomize_va_space)" | head -10 >> "$output_file"
    echo '```' >> "$output_file"
    echo "" >> "$output_file"

    # Document AppArmor profiles
    if command -v aa-status &>/dev/null; then
        echo "### 6. AppArmor" >> "$output_file"
        echo "" >> "$output_file"
        echo "#### Profile Summary" >> "$output_file"
        echo '```' >> "$output_file"
        sudo aa-status --summary 2>/dev/null >> "$output_file"
        echo '```' >> "$output_file"
        echo "" >> "$output_file"
    fi

    # Document audit rules
    if command -v auditctl &>/dev/null; then
        echo "### 7. Audit System" >> "$output_file"
        echo "" >> "$output_file"
        echo "#### Active Rules Count" >> "$output_file"
        echo '```' >> "$output_file"
        sudo auditctl -l 2>/dev/null | wc -l >> "$output_file"
        echo '```' >> "$output_file"
        echo "" >> "$output_file"
    fi

    print_success "Security documentation generated"
    return 0
}

# ============================================================================
# Configuration Documentation
# ============================================================================

# Document system configuration
document_configuration() {
    local output_file="${1:-$DOC_OUTPUT_DIR/markdown/configuration.md}"

    print_status "Documenting system configuration..."

    cat << 'EOF' > "$output_file"
# System Configuration Documentation

## Configuration Files

This section documents key configuration files and their purposes.

EOF

    # Document important config files
    local config_files=(
        "/etc/ssh/sshd_config:SSH Server Configuration"
        "/etc/ufw/ufw.conf:UFW Firewall Configuration"
        "/etc/fail2ban/jail.local:Fail2ban Jail Configuration"
        "/etc/docker/daemon.json:Docker Daemon Configuration"
        "/etc/containers/registries.conf:Podman Registries"
        "/etc/systemd/system.conf:Systemd Configuration"
        "/etc/security/limits.conf:Security Limits"
        "/etc/sysctl.conf:Kernel Parameters"
        "/etc/fstab:Filesystem Mounts"
        "/etc/hosts:Host Mappings"
        "/etc/hostname:System Hostname"
        "/etc/resolv.conf:DNS Configuration"
    )

    for config_entry in "${config_files[@]}"; do
        local file="${config_entry%%:*}"
        local description="${config_entry#*:}"

        if [ -f "$file" ]; then
            echo "### $description" >> "$output_file"
            echo "" >> "$output_file"
            echo "**File:** \`$file\`" >> "$output_file"
            echo "" >> "$output_file"
            echo "**Last Modified:** $(stat -c %y "$file" | cut -d' ' -f1)" >> "$output_file"
            echo "" >> "$output_file"
            echo "**Permissions:** $(stat -c %a "$file")" >> "$output_file"
            echo "" >> "$output_file"
            echo "**Size:** $(du -h "$file" | awk '{print $1}')" >> "$output_file"
            echo "" >> "$output_file"

            # Show first 20 lines of config (excluding comments)
            echo "**Key Settings:**" >> "$output_file"
            echo '```' >> "$output_file"
            grep -v "^#" "$file" 2>/dev/null | grep -v "^$" | head -20 >> "$output_file"
            echo '```' >> "$output_file"
            echo "" >> "$output_file"
            echo "---" >> "$output_file"
            echo "" >> "$output_file"
        fi
    done

    print_success "Configuration documentation generated"
    return 0
}

# ============================================================================
# Network Documentation
# ============================================================================

# Document network configuration
document_network() {
    local output_file="${1:-$DOC_OUTPUT_DIR/markdown/network.md}"

    print_status "Documenting network configuration..."

    cat << 'EOF' > "$output_file"
# Network Configuration Documentation

## Network Overview

EOF

    # Network interfaces
    echo "### Network Interfaces" >> "$output_file"
    echo '```' >> "$output_file"
    ip addr show >> "$output_file"
    echo '```' >> "$output_file"
    echo "" >> "$output_file"

    # Routing table
    echo "### Routing Table" >> "$output_file"
    echo '```' >> "$output_file"
    ip route show >> "$output_file"
    echo '```' >> "$output_file"
    echo "" >> "$output_file"

    # Open ports
    echo "### Open Ports" >> "$output_file"
    echo '```' >> "$output_file"
    ss -tulpn 2>/dev/null | grep LISTEN >> "$output_file"
    echo '```' >> "$output_file"
    echo "" >> "$output_file"

    # DNS configuration
    echo "### DNS Configuration" >> "$output_file"
    echo '```' >> "$output_file"
    cat /etc/resolv.conf >> "$output_file"
    echo '```' >> "$output_file"
    echo "" >> "$output_file"

    # Firewall rules
    echo "### Firewall Rules" >> "$output_file"
    echo '```' >> "$output_file"
    sudo iptables -L -n -v 2>/dev/null | head -50 >> "$output_file"
    echo '```' >> "$output_file"
    echo "" >> "$output_file"

    # Network connections
    echo "### Active Connections" >> "$output_file"
    echo '```' >> "$output_file"
    ss -tun | head -20 >> "$output_file"
    echo '```' >> "$output_file"
    echo "" >> "$output_file"

    print_success "Network documentation generated"
    return 0
}

# ============================================================================
# Service Documentation
# ============================================================================

# Document system services
document_services() {
    local output_file="${1:-$DOC_OUTPUT_DIR/markdown/services.md}"

    print_status "Documenting system services..."

    cat << 'EOF' > "$output_file"
# System Services Documentation

## Service Overview

EOF

    # Active services
    echo "### Active Services" >> "$output_file"
    echo '```' >> "$output_file"
    systemctl list-units --type=service --state=active --no-pager --no-legend | head -30 >> "$output_file"
    echo '```' >> "$output_file"
    echo "" >> "$output_file"

    # Failed services
    echo "### Failed Services" >> "$output_file"
    echo '```' >> "$output_file"
    systemctl list-units --type=service --state=failed --no-pager --no-legend >> "$output_file" || echo "No failed services" >> "$output_file"
    echo '```' >> "$output_file"
    echo "" >> "$output_file"

    # Critical service details
    echo "## Critical Services" >> "$output_file"
    echo "" >> "$output_file"

    local critical_services=(
        "sshd"
        "ufw"
        "docker"
        "podman"
        "nginx"
        "apache2"
        "mysql"
        "postgresql"
        "fail2ban"
        "crowdsec"
        "clamav-daemon"
    )

    for service in "${critical_services[@]}"; do
        if systemctl is-enabled "$service" &>/dev/null; then
            echo "### $service" >> "$output_file"
            echo "" >> "$output_file"
            echo "**Status:** $(systemctl is-active $service)" >> "$output_file"
            echo "**Enabled:** $(systemctl is-enabled $service)" >> "$output_file"

            # Get service uptime
            local start_time=$(systemctl show "$service" --property=ActiveEnterTimestamp --value)
            if [ -n "$start_time" ] && [ "$start_time" != "n/a" ]; then
                echo "**Started:** $start_time" >> "$output_file"
            fi

            # Get memory usage
            local mem=$(systemctl show "$service" --property=MemoryCurrent --value)
            if [ -n "$mem" ] && [ "$mem" != "[not set]" ]; then
                echo "**Memory:** $(numfmt --to=iec-i --suffix=B $mem 2>/dev/null || echo $mem)" >> "$output_file"
            fi

            echo "" >> "$output_file"
        fi
    done

    print_success "Service documentation generated"
    return 0
}

# ============================================================================
# Container Documentation
# ============================================================================

# Document containers
document_containers() {
    local output_file="${1:-$DOC_OUTPUT_DIR/markdown/containers.md}"

    print_status "Documenting containers..."

    cat << 'EOF' > "$output_file"
# Container Configuration Documentation

## Container Runtimes

EOF

    # Docker
    if command -v docker &>/dev/null; then
        echo "### Docker" >> "$output_file"
        echo "" >> "$output_file"
        echo "**Version:** $(docker --version)" >> "$output_file"
        echo "" >> "$output_file"
        echo "#### Running Containers" >> "$output_file"
        echo '```' >> "$output_file"
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null >> "$output_file"
        echo '```' >> "$output_file"
        echo "" >> "$output_file"
        echo "#### Images" >> "$output_file"
        echo '```' >> "$output_file"
        docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" 2>/dev/null | head -20 >> "$output_file"
        echo '```' >> "$output_file"
        echo "" >> "$output_file"
    fi

    # Podman
    if command -v podman &>/dev/null; then
        echo "### Podman" >> "$output_file"
        echo "" >> "$output_file"
        echo "**Version:** $(podman --version)" >> "$output_file"
        echo "" >> "$output_file"
        echo "#### Running Containers" >> "$output_file"
        echo '```' >> "$output_file"
        podman ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null >> "$output_file"
        echo '```' >> "$output_file"
        echo "" >> "$output_file"
        echo "#### Pods" >> "$output_file"
        echo '```' >> "$output_file"
        podman pod ps 2>/dev/null >> "$output_file"
        echo '```' >> "$output_file"
        echo "" >> "$output_file"
    fi

    print_success "Container documentation generated"
    return 0
}

# ============================================================================
# Dependency Graph
# ============================================================================

# Generate module dependency graph
generate_dependency_graph() {
    local output_file="${1:-$DOC_OUTPUT_DIR/module-dependencies.dot}"

    print_status "Generating module dependency graph..."

    cat << 'EOF' > "$output_file"
digraph ModuleDependencies {
    rankdir=LR;
    node [shape=box, style=rounded];

    // Core libraries
    subgraph cluster_lib {
        label="Libraries";
        style=filled;
        color=lightgrey;
        "common.sh" [style=filled, fillcolor=lightblue];
        "config.sh" [style=filled, fillcolor=lightblue];
        "validation.sh" [style=filled, fillcolor=lightblue];
        "backup.sh" [style=filled, fillcolor=lightblue];
    }

    // Base modules
    subgraph cluster_base {
        label="Base Modules";
        style=filled;
        color=lightgreen;
        "system-update.sh";
        "shell-setup.sh";
        "dev-tools.sh";
        "user-setup.sh";
        "timezone-locale.sh";
    }

    // Security modules
    subgraph cluster_security {
        label="Security Modules";
        style=filled;
        color=lightyellow;
        "firewall.sh";
        "ssh-security.sh";
        "system-hardening.sh";
        "tailscale.sh";
        "cloudflare.sh";
        "crowdsec.sh";
        "fail2ban.sh";
        "aide.sh";
        "clamav.sh";
    }

    // Dependencies
    "system-update.sh" -> "common.sh";
    "shell-setup.sh" -> "common.sh";
    "dev-tools.sh" -> "common.sh";
    "firewall.sh" -> {"common.sh", "config.sh"};
    "ssh-security.sh" -> {"common.sh", "backup.sh"};
    "system-hardening.sh" -> {"common.sh", "validation.sh"};

    // Orchestration
    "setup.sh" -> {"system-update.sh", "shell-setup.sh", "dev-tools.sh"};
    "zero-trust.sh" -> {"firewall.sh", "ssh-security.sh", "system-hardening.sh"};
}
EOF

    # Generate SVG from DOT file
    if command -v dot &>/dev/null; then
        dot -Tsvg "$output_file" -o "${output_file%.dot}.svg"
        dot -Tpng "$output_file" -o "${output_file%.dot}.png"
        print_success "Dependency graph generated"
    else
        print_warning "Graphviz not installed, skipping graph generation"
    fi

    return 0
}

# ============================================================================
# HTML Generation
# ============================================================================

# Generate HTML documentation
generate_html() {
    print_header "Generating HTML Documentation"

    # Create HTML template
    cat << 'EOF' > "$DOC_OUTPUT_DIR/html/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Documentation</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        h3 { color: #7f8c8d; }
        pre {
            background: #2c3e50;
            color: #ecf0f1;
            padding: 15px;
            border-radius: 5px;
            overflow-x: auto;
        }
        code {
            background: #ecf0f1;
            padding: 2px 5px;
            border-radius: 3px;
        }
        .nav {
            background: white;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .nav a {
            margin-right: 15px;
            color: #3498db;
            text-decoration: none;
        }
        .nav a:hover { text-decoration: underline; }
        .section {
            background: white;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .status-active { color: #27ae60; }
        .status-inactive { color: #e74c3c; }
        .metric {
            display: inline-block;
            padding: 10px 20px;
            background: #3498db;
            color: white;
            border-radius: 5px;
            margin: 5px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
        }
        th, td {
            padding: 10px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background: #34495e;
            color: white;
        }
        tr:hover { background: #f5f5f5; }
    </style>
</head>
<body>
    <div class="nav">
        <a href="#overview">Overview</a>
        <a href="#modules">Modules</a>
        <a href="#security">Security</a>
        <a href="#services">Services</a>
        <a href="#network">Network</a>
        <a href="#containers">Containers</a>
    </div>

    <h1>System Documentation</h1>
    <p>Generated: <strong>$(date)</strong></p>
    <p>Hostname: <strong>$(hostname -f)</strong></p>

    <div class="section" id="overview">
        <h2>System Overview</h2>
        <div class="metric">OS: $(lsb_release -ds 2>/dev/null)</div>
        <div class="metric">Kernel: $(uname -r)</div>
        <div class="metric">Uptime: $(uptime -p)</div>
        <div class="metric">Load: $(uptime | awk -F'load average:' '{print $2}')</div>
    </div>

    <div class="section" id="modules">
        <h2>Installed Modules</h2>
        <table>
            <tr>
                <th>Module</th>
                <th>Category</th>
                <th>Lines</th>
                <th>Functions</th>
            </tr>
EOF

    # Add module information to HTML
    for module in $(find /home/ubuntu/server-config/src -name "*.sh" -type f | sort); do
        local module_name=$(basename "$module")
        local module_dir=$(dirname "$module" | xargs basename)
        local line_count=$(wc -l < "$module")
        local function_count=$(grep -c "^[a-z_]*() {" "$module")

        echo "            <tr>" >> "$DOC_OUTPUT_DIR/html/index.html"
        echo "                <td>$module_name</td>" >> "$DOC_OUTPUT_DIR/html/index.html"
        echo "                <td>$module_dir</td>" >> "$DOC_OUTPUT_DIR/html/index.html"
        echo "                <td>$line_count</td>" >> "$DOC_OUTPUT_DIR/html/index.html"
        echo "                <td>$function_count</td>" >> "$DOC_OUTPUT_DIR/html/index.html"
        echo "            </tr>" >> "$DOC_OUTPUT_DIR/html/index.html"
    done

    echo "        </table>" >> "$DOC_OUTPUT_DIR/html/index.html"
    echo "    </div>" >> "$DOC_OUTPUT_DIR/html/index.html"
    echo "</body>" >> "$DOC_OUTPUT_DIR/html/index.html"
    echo "</html>" >> "$DOC_OUTPUT_DIR/html/index.html"

    # Convert markdown files to HTML
    for md_file in "$DOC_OUTPUT_DIR/markdown"/*.md; do
        if [ -f "$md_file" ]; then
            local html_file="$DOC_OUTPUT_DIR/html/$(basename "${md_file%.md}.html")"
            if command -v pandoc &>/dev/null; then
                pandoc -f markdown -t html5 \
                    --standalone \
                    --toc \
                    --metadata title="$(basename "${md_file%.md}")" \
                    "$md_file" -o "$html_file"
            fi
        fi
    done

    print_success "HTML documentation generated"
    return 0
}

# ============================================================================
# PDF Generation
# ============================================================================

# Generate PDF documentation
generate_pdf() {
    print_header "Generating PDF Documentation"

    if ! command -v pandoc &>/dev/null; then
        print_error "Pandoc not installed, cannot generate PDF"
        return 1
    fi

    # Combine all markdown files
    local combined_md="$DOC_OUTPUT_DIR/combined.md"

    cat << EOF > "$combined_md"
---
title: System Documentation
author: $(hostname -f)
date: $(date +%Y-%m-%d)
---

EOF

    # Add all markdown files
    for md_file in "$DOC_OUTPUT_DIR/markdown"/*.md; do
        if [ -f "$md_file" ]; then
            echo "" >> "$combined_md"
            cat "$md_file" >> "$combined_md"
            echo "" >> "$combined_md"
            echo "\\newpage" >> "$combined_md"
        fi
    done

    # Generate PDF
    if command -v pdflatex &>/dev/null; then
        pandoc "$combined_md" \
            --pdf-engine=pdflatex \
            --toc \
            --toc-depth=3 \
            -o "$DOC_OUTPUT_DIR/pdf/system-documentation.pdf"
    elif command -v wkhtmltopdf &>/dev/null; then
        # Fallback to wkhtmltopdf
        pandoc "$combined_md" -t html5 | \
            wkhtmltopdf - "$DOC_OUTPUT_DIR/pdf/system-documentation.pdf"
    else
        print_warning "No PDF generator available"
    fi

    # Clean up
    rm -f "$combined_md"

    if [ -f "$DOC_OUTPUT_DIR/pdf/system-documentation.pdf" ]; then
        print_success "PDF documentation generated"
    else
        print_error "Failed to generate PDF"
        return 1
    fi

    return 0
}

# ============================================================================
# Complete Documentation
# ============================================================================

# Generate complete documentation
generate_complete_docs() {
    print_header "Generating Complete Documentation"

    # Setup directories
    setup_directories

    # Gather system information
    gather_system_info

    # Generate all documentation sections
    document_modules
    document_security
    document_configuration
    document_network
    document_services
    document_containers

    # Generate dependency graph
    generate_dependency_graph

    # Generate HTML documentation
    if confirm_action "Generate HTML documentation?"; then
        generate_html
    fi

    # Generate PDF documentation
    if confirm_action "Generate PDF documentation?"; then
        generate_pdf
    fi

    # Create index file
    cat << EOF > "$DOC_OUTPUT_DIR/README.md"
# System Documentation

Generated: $(date)

## Available Formats

- **Markdown**: $DOC_OUTPUT_DIR/markdown/
- **HTML**: $DOC_OUTPUT_DIR/html/
- **PDF**: $DOC_OUTPUT_DIR/pdf/
- **JSON**: $DOC_OUTPUT_DIR/json/

## Contents

1. **modules.md** - Module documentation
2. **security.md** - Security configuration
3. **configuration.md** - System configuration
4. **network.md** - Network configuration
5. **services.md** - Service documentation
6. **containers.md** - Container configuration

## Viewing Documentation

### Markdown
\`\`\`bash
cat $DOC_OUTPUT_DIR/markdown/modules.md
\`\`\`

### HTML
\`\`\`bash
xdg-open $DOC_OUTPUT_DIR/html/index.html
\`\`\`

### PDF
\`\`\`bash
xdg-open $DOC_OUTPUT_DIR/pdf/system-documentation.pdf
\`\`\`

## Regenerating Documentation

\`\`\`bash
sudo bash $(realpath "${BASH_SOURCE[0]}") --complete
\`\`\`
EOF

    print_success "Complete documentation generated!"
    echo ""
    echo "Documentation location: $DOC_OUTPUT_DIR"
    echo ""
    echo "Available formats:"
    echo "  - Markdown: $DOC_OUTPUT_DIR/markdown/"
    echo "  - HTML: $DOC_OUTPUT_DIR/html/"
    echo "  - PDF: $DOC_OUTPUT_DIR/pdf/"
    echo "  - JSON: $DOC_OUTPUT_DIR/json/"

    return 0
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Documentation Generator Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --setup                 Setup documentation directories
    --install               Install documentation tools
    --system-info           Gather system information
    --modules               Document all modules
    --security              Document security configuration
    --configuration         Document system configuration
    --network               Document network configuration
    --services              Document system services
    --containers            Document container configuration
    --dependency-graph      Generate module dependency graph
    --html                  Generate HTML documentation
    --pdf                   Generate PDF documentation
    --complete              Generate complete documentation
    --help                  Show this help message
    --test                  Run module self-test

EXAMPLES:
    # Generate complete documentation
    $0 --complete

    # Generate specific documentation
    $0 --modules
    $0 --security

    # Generate HTML format
    $0 --html

    # Generate PDF format
    $0 --pdf

OUTPUT LOCATIONS:
    Markdown: $DOC_OUTPUT_DIR/markdown/
    HTML: $DOC_OUTPUT_DIR/html/
    PDF: $DOC_OUTPUT_DIR/pdf/
    JSON: $DOC_OUTPUT_DIR/json/

EOF
}

# Run self-test
run_self_test() {
    print_header "Running Documentation Module Self-Test"

    local tests_passed=0
    local tests_failed=0

    # Test: Check for required commands
    for cmd in pandoc jq; do
        if command -v $cmd &>/dev/null; then
            ((tests_passed++))
            print_success "Command available: $cmd"
        else
            ((tests_failed++))
            print_warning "Command missing: $cmd (optional)"
        fi
    done

    # Test: Check write permissions
    if [ -w "/var/lib" ]; then
        ((tests_passed++))
        print_success "Can write to /var/lib"
    else
        ((tests_failed++))
        print_error "Cannot write to /var/lib"
    fi

    # Test: Check module directory exists
    if [ -d "/home/ubuntu/server-config/src" ]; then
        ((tests_passed++))
        print_success "Module directory exists"
    else
        ((tests_failed++))
        print_error "Module directory not found"
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
export -f setup_directories install_doc_tools
export -f gather_system_info document_modules
export -f document_security document_configuration
export -f document_network document_services document_containers
export -f generate_dependency_graph generate_html generate_pdf
export -f generate_complete_docs

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
        --setup)
            setup_directories
            ;;
        --install)
            install_doc_tools
            ;;
        --system-info)
            gather_system_info
            ;;
        --modules)
            document_modules
            ;;
        --security)
            document_security
            ;;
        --configuration)
            document_configuration
            ;;
        --network)
            document_network
            ;;
        --services)
            document_services
            ;;
        --containers)
            document_containers
            ;;
        --dependency-graph)
            generate_dependency_graph
            ;;
        --html)
            generate_html
            ;;
        --pdf)
            generate_pdf
            ;;
        --complete)
            generate_complete_docs
            ;;
        --help)
            show_help
            ;;
        --test)
            run_self_test
            ;;
        *)
            echo "Documentation Generator Module v${MODULE_VERSION}"
            echo "Run with --help for usage information"
            ;;
    esac
fi
