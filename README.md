# Ubuntu Server Setup Script

Automated setup script for Ubuntu servers with Zsh, development tools, and security configurations.

## Quick Start

```bash
rm -rf server-config && git clone https://github.com/abd3lraouf/server-config.git && cd server-config && chmod +x setup.sh && sudo ./setup.sh
```

## Features

### Base Configuration
- System updates and package management
- Zsh shell with Oh-My-Zsh framework
- Powerlevel10k theme with plugins (autosuggestions, syntax highlighting, completions)
- NVM, Node.js LTS, and Claude Code CLI
- htop system monitor
- Coolify self-hosting platform
- APT sources cleanup

### Security Configuration  
- UFW firewall (SSH-only by default)
- SSH hardening for Coolify compatibility

## Menu Structure

```
Main Menu
├── 1) Base Configuration
│   ├── System Update
│   ├── Zsh & Oh-My-Zsh
│   ├── Powerlevel10k
│   ├── Configuration Files
│   ├── NVM & Node.js
│   ├── Claude Code CLI
│   ├── htop
│   ├── Coolify
│   └── APT Cleanup
├── 2) Security Configuration
│   ├── UFW Firewall
│   └── SSH Hardening
└── 3) Run All Steps
```

## Prerequisites

- Ubuntu Server 20.04+ 
- Root/sudo access
- Internet connection

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