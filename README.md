# Ubuntu Server Zero Trust Security Setup Script v2.1.0

Enterprise-grade automated security hardening for Ubuntu 24.04 LTS servers with comprehensive Zero Trust architecture, CIS benchmark compliance, and interactive configuration wizard.

## 🚀 Quick Start

### Interactive Setup (Recommended)
```bash
git clone https://github.com/abd3lraouf/server-config.git && cd server-config
sudo ./setup.sh
```

### Automated Zero Trust Setup
```bash
sudo ./setup.sh --quick-setup --email admin@example.com --domain example.com
```

## ✨ Features

### 🔒 Zero Trust Security Architecture
- **Zero exposed ports** - All traffic via secure tunnels
- **Tailscale VPN** - Secure SSH access with MFA support
- **Cloudflare Tunnel** - Protected web services without exposed ports
- **CrowdSec IPS** - Real-time threat detection and blocking
- **UFW-Docker Integration** - Proper firewall rules for containers
- **Multi-layer defense** - Defense in depth strategy

### 📋 Compliance & Hardening
- **CIS Ubuntu 24.04 LTS Benchmarks** - Automated Level 1 & 2 controls
- **NIST SP 800-207** - Zero Trust Architecture implementation
- **Kernel hardening** - Ubuntu 24.04 kernel 6.8+ optimizations
- **AppArmor 4.0** - Mandatory Access Control enforcement
- **Audit system** - Comprehensive logging with auditd
- **File integrity** - AIDE monitoring for critical files
- **Automatic updates** - Unattended security patches

### 🐳 Container Security
- **Rootless Docker** - Enhanced security without root privileges
- **Podman support** - Alternative container runtime (rootless by default)
- **Container scanning** - Security validation for images
- **Network isolation** - Secure container networking

### 📊 Monitoring & Reporting
- **Compliance scoring** - HTML/text reports with 85%+ target
- **Lynis auditing** - Security hardening assessment
- **Logwatch analysis** - Automated log review
- **Real-time validation** - Continuous security checks
- **Emergency rollback** - Safe recovery procedures

### Base Configuration
- System updates and package management
- Zsh shell with Oh-My-Zsh framework
- Powerlevel10k theme with plugins
- NVM, Node.js LTS, and Claude Code CLI
- htop system monitor
- Coolify self-hosting platform

## 📚 Menu Structure

```
Main Menu
├── 1) Base Configuration
│   ├── System Update
│   ├── Zsh & Oh-My-Zsh
│   ├── Development Tools
│   └── Coolify Platform
├── 2) Security Configuration
│   ├── Basic Security
│   ├── Zero Trust Setup (Complete)
│   ├── CIS Benchmarks
│   ├── Compliance Reporting
│   ├── Container Runtime
│   ├── Emergency Rollback
│   └── Individual Components:
│       ├── System Hardening
│       ├── UFW-Docker Firewall
│       ├── Tailscale VPN
│       ├── Cloudflare Tunnel
│       ├── CrowdSec IPS
│       └── Monitoring Tools
└── 3) Run All Steps
```

## 🔧 Prerequisites

- **Ubuntu 24.04 LTS** (Noble Numbat) - Required
- **Ubuntu 22.04/20.04** - Supported with limitations
- **Root/sudo access**
- **4GB RAM minimum** (8GB recommended)
- **40GB storage minimum**
- **Internet connection**

## Required Files

The script needs these configuration files (included in repo):
- `setup.sh` - Main script
- `zshrc` - Zsh configuration
- `p10k.zsh` - Powerlevel10k theme

## Usage

### Interactive Mode
```bash
sudo ./setup.sh
```

### One-Liner Examples

**Full installation:**
```bash
rm -rf server-config && git clone https://github.com/abd3lraouf/server-config.git && cd server-config && chmod +x setup.sh && sudo ./setup.sh
```

**Security only:**
```bash
# After cloning, run security menu
sudo bash -c './setup.sh <<< "2\n3"'
```

## Post-Installation

1. **Log out and back in** for shell changes
2. **Configure Powerlevel10k** (optional): `p10k configure`
3. **Login to Claude**: `claude login`
4. **Access Coolify**: `http://your-server-ip:8000`

## Backups

All existing configs are backed up to:
```
~/.config-backup-YYYYMMDD-HHMMSS/
```

## Security Notes

- UFW blocks all incoming except SSH (port 22)
- SSH root login requires keys (no passwords)
- Coolify adds ports 80, 443, 8000 to firewall
- Review scripts before running with sudo

## Troubleshooting

**Shell not changed:**
```bash
chsh -s $(which zsh)
# Then log out and back in
```

**Theme not loading:**
```bash
source ~/.zshrc
```

**Best fonts:** Install [Nerd Fonts](https://www.nerdfonts.com/) for icons

## System Requirements

- **RAM**: 1GB minimum (2GB with Coolify)
- **Disk**: 500MB base, 2GB+ with Coolify
- **Network**: SSH port 22 accessible

## Support

For issues: https://github.com/abd3lraouf/server-config/issues

---
**Note**: Always review scripts before running with sudo privileges.