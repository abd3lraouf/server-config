# Ubuntu Server Setup 🚀

[![Version](https://img.shields.io/badge/version-2.1.0-blue)](https://github.com/abd3lraouf/server-config)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%20|%2022.04%20|%2024.04-orange)](https://ubuntu.com/)
[![Modules](https://img.shields.io/badge/modules-33-green)](./src)
[![License](https://img.shields.io/badge/license-MIT-lightgray)](./LICENSE)

**Enterprise-grade modular server configuration system for Ubuntu with Zero Trust security architecture.**

## 🎯 One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/abd3lraouf/server-config/main/setup.sh | sudo bash
```

Or with wget:
```bash
wget -qO- https://raw.githubusercontent.com/abd3lraouf/server-config/main/setup.sh | sudo bash
```

## 🚀 Quick Start Options

### Interactive Menu (Default)
```bash
curl -fsSL https://raw.githubusercontent.com/abd3lraouf/server-config/main/setup.sh | sudo bash
```

### Specific Configurations
```bash
# Basic setup (system updates, shell, dev tools)
curl -fsSL https://raw.githubusercontent.com/abd3lraouf/server-config/main/setup.sh | sudo bash -s -- basic

# Security hardening
curl -fsSL https://raw.githubusercontent.com/abd3lraouf/server-config/main/setup.sh | sudo bash -s -- security

# Complete Zero Trust setup
curl -fsSL https://raw.githubusercontent.com/abd3lraouf/server-config/main/setup.sh | sudo bash -s -- zero-trust

# Development environment
curl -fsSL https://raw.githubusercontent.com/abd3lraouf/server-config/main/setup.sh | sudo bash -s -- development
```

## 📦 What's Included

### 🏗️ Modular Architecture
**33 professional modules** organized into 7 categories, each module is self-contained and testable:

```
src/
├── 📚 lib/          # Core libraries (4 modules)
├── 🖥️  base/        # System setup (5 modules)
├── 🔐 security/     # Security hardening (10 modules)
├── 🐳 containers/   # Container platforms (3 modules)
├── 📊 monitoring/   # Monitoring & compliance (4 modules)
├── 🎛️  menu/        # User interfaces (4 modules)
└── 🔧 scripts/      # Orchestration (3 modules)
```

### ✨ Key Features

#### 🔒 **Zero Trust Security**
- Tailscale VPN with MFA
- Cloudflare Tunnel (zero exposed ports)
- CrowdSec intrusion prevention
- UFW-Docker firewall integration
- SSH hardening & key management
- Fail2ban brute-force protection

#### 🛡️ **Compliance & Hardening**
- CIS Ubuntu Benchmarks (Level 1 & 2)
- NIST SP 800-207 compliance
- Kernel security parameters
- AppArmor mandatory access control
- AIDE file integrity monitoring
- Automated security updates

#### 🐳 **Container Support**
- Docker with security best practices
- Podman rootless containers
- Coolify self-hosting platform
- Container network isolation

#### 📊 **Monitoring & Auditing**
- Lynis security auditing
- Logwatch log analysis
- Compliance reporting (85%+ target)
- Real-time security validation

#### 💻 **Development Environment**
- Zsh + Oh-My-Zsh + Powerlevel10k
- NVM + Node.js LTS
- Claude CLI integration
- Modern development tools

## 📋 System Requirements

- **OS**: Ubuntu 20.04 LTS, 22.04 LTS, or 24.04 LTS (recommended)
- **RAM**: 4GB minimum (8GB recommended for full Zero Trust)
- **Storage**: 40GB minimum
- **Access**: Root or sudo privileges
- **Network**: Internet connection for package downloads

## 🎯 Usage Examples

### Run Individual Modules
```bash
# First, clone the repository if running modules directly
git clone https://github.com/abd3lraouf/server-config.git
cd server-config

# Install Docker
sudo bash src/containers/docker.sh --install

# Harden SSH
sudo bash src/security/ssh-security.sh --harden

# Setup Tailscale VPN
sudo bash src/security/tailscale.sh --interactive

# Run security audit
sudo bash src/monitoring/lynis.sh --audit
```

### Module Self-Tests
Every module includes built-in testing:
```bash
sudo bash src/security/firewall.sh --test
sudo bash src/containers/docker.sh --test
```

## 🏗️ Architecture Overview

This system transforms a monolithic 4,294-line script into a professional modular architecture with:

- **100% module completion** - All 33 modules fully implemented
- **~24,000+ lines** of production-ready code
- **Clean separation** of concerns
- **Consistent interface** - All modules support `--help`, `--test`, and function flags
- **Self-contained** - Each module can run standalone or be sourced
- **Enterprise-grade** security with defense in depth

## 🔐 Security Considerations

- All SSH connections require key-based authentication
- Firewall blocks all incoming traffic except SSH (port 22)
- Web services are exposed only through secure tunnels
- Automatic security updates are configured
- All configurations are backed up before changes
- Coolify-compatible SSH settings are preserved

## 📚 Documentation

Each module includes comprehensive help:
```bash
sudo bash src/security/ssh-security.sh --help
sudo bash src/containers/docker.sh --help
```

For detailed module documentation, see [MODULE_STATUS.md](./MODULE_STATUS.md)

## 🤝 Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request

## 📄 License

MIT License - See [LICENSE](./LICENSE) file for details

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/abd3lraouf/server-config/issues)
- **Discussions**: [GitHub Discussions](https://github.com/abd3lraouf/server-config/discussions)

## ⚠️ Important Notes

1. **Always review scripts** before running with sudo privileges
2. **Backups are created** in `~/.config-backup-YYYYMMDD-HHMMSS/`
3. **Log out and back in** after shell changes take effect
4. **Test in a VM** before running on production servers

---

<div align="center">
  <strong>Built with ❤️ for the Ubuntu community</strong>
  <br>
  <sub>Transforming server setup from complexity to simplicity</sub>
</div>