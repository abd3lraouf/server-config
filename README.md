# Ubuntu Server Setup Script

A comprehensive setup script for configuring Ubuntu Server with Zsh, Oh-My-Zsh, Powerlevel10k theme, and essential plugins.

## Features

- 🚀 **Interactive Menu System** - Choose which components to install
- 🎨 **Powerlevel10k Theme** - Beautiful and fast Zsh theme
- 🔌 **Essential Plugins** - Auto-suggestions, syntax highlighting, and completions
- 👥 **Multi-User Support** - Configures both root and main user
- 💾 **Automatic Backups** - Backs up existing configurations before changes
- 🔄 **System Updates** - Complete apt update, upgrade, and cleanup
- 📦 **NVM & Node.js** - Node Version Manager with latest LTS Node.js
- 🤖 **Claude CLI** - Anthropic's Claude CLI for AI assistance
- 📊 **System Monitoring** - htop for interactive process viewing
- 🔥 **UFW Firewall** - Automated firewall configuration for security
- 🔐 **SSH Hardening** - Secure SSH configuration for Coolify compatibility
- 🚀 **Coolify Platform** - Self-hosted Heroku/Netlify/Vercel alternative
- 🧹 **APT Sources Cleanup** - Removes duplicate and obsolete APT sources

## Quick Start (One-liner)

### Full Installation (All Features)
```bash
git clone https://github.com/abd3lraouf/server-config.git && cd server-config && chmod +x setup.sh && sudo ./setup.sh
```

### Security-First Installation (Firewall + SSH + Coolify)
```bash
git clone https://github.com/abd3lraouf/server-config.git && cd server-config && chmod +x setup.sh && sudo bash -c './setup.sh <<< "10"' && sudo bash -c './setup.sh <<< "11"' && sudo bash -c './setup.sh <<< "12"'
```

Or download and run with wget:

```bash
wget https://raw.githubusercontent.com/abd3lraouf/server-config/main/setup.sh -O setup.sh && chmod +x setup.sh && sudo ./setup.sh
```

Or if you have the files locally:

```bash
chmod +x setup.sh && sudo ./setup.sh
```

## Prerequisites

- Ubuntu Server (20.04 LTS or newer recommended)
- Root or sudo access
- Internet connection (for downloading packages)

## Required Files

Place these files in the same directory as `setup.sh`:

1. **setup.sh** - Main installation script
2. **zshrc** or **.zshrc** - Zsh configuration file
3. **p10k.zsh** or **.p10k.zsh** - Powerlevel10k configuration
4. **aptsources-cleanup.pyz** - APT sources cleanup tool (optional, will be downloaded if not present)

## Installation Options

The script provides an interactive menu with the following options:

### 1. System Update
- Runs `apt update` to refresh package lists
- Performs `apt upgrade -y` to update all packages
- Executes `apt autoremove` and `apt autoclean` for cleanup
- Essential first step for any new server setup

### 2. Install Zsh
- Installs Zsh package
- Sets Zsh as default shell for root and main user
- Automatically detects the main non-root user

### 3. Install Oh-My-Zsh
- Downloads and installs Oh-My-Zsh framework
- Installs three essential plugins:
  - **zsh-autosuggestions** - Fish-like autosuggestions
  - **zsh-completions** - Additional completion definitions
  - **zsh-syntax-highlighting** - Fish shell-like syntax highlighting

### 4. Install Powerlevel10k
- Clones the Powerlevel10k repository
- Sets up the theme for both root and main user
- Provides a beautiful, customizable prompt

### 5. Deploy Configuration Files
- Copies `.zshrc` to user home directories
- Copies `.p10k.zsh` configuration
- Maintains proper file permissions and ownership
- Creates backups of existing configurations

### 6. Install NVM (Node Version Manager)
- Downloads and installs NVM v0.40.3
- Configures NVM for both root and main user
- Adds NVM configuration to `.zshrc`
- Enables easy Node.js version management

### 7. Install Node.js
- Installs latest LTS version of Node.js via NVM
- Sets LTS as the default Node.js version
- Configures for both root and main user
- Required for Claude CLI and modern development

### 8. Install Claude CLI
- Installs Claude CLI globally via npm
- Provides command-line access to Claude AI
- Configures for both root and main user
- Remember to run `claude login` after installation

### 9. Install htop
- Installs htop interactive process viewer
- Provides real-time system monitoring
- Better alternative to traditional top command
- Color-coded resource usage display

### 10. Configure UFW Firewall
- Installs and configures UFW (Uncomplicated Firewall)
- Sets default policies: deny incoming, allow outgoing
- **Only allows SSH (port 22) by default**
- Automatically enables firewall protection
- Additional ports opened for Coolify if installed

### 11. Configure SSH for Coolify
- Configures OpenSSH for Coolify compatibility
- Sets `PermitRootLogin prohibit-password` for security
- Enables `PubkeyAuthentication`
- Generates ED25519 SSH keys if needed
- Adds keys to authorized_keys automatically
- **Warning**: Ensure you have SSH key access before running

### 12. Install Coolify
- Installs Coolify self-hosting platform
- Includes Docker and Docker Compose installation
- Configures SSH keys for Coolify operations
- Opens required firewall ports (80, 443, 8000)
- Provides:
  - Application deployment from Git
  - Database management
  - One-click service deployments
  - SSL certificate management
  - Multi-server support
- Access dashboard at `http://your-server-ip:8000`

### 13. Clean APT Sources
- Installs `python3-apt` dependency
- Downloads `aptsources-cleanup.pyz` if not present
- Removes duplicate and obsolete APT sources
- Helps maintain a clean package management system

### 14. Run All Steps
- Executes all installation steps in sequence
- Recommended for fresh server setups

## Usage

### Interactive Mode

Run the script with sudo privileges:

```bash
sudo ./setup.sh
```

Then select options from the menu:

```
╔══════════════════════════════════════════════════╗
║          Ubuntu Server Setup Script              ║
╚══════════════════════════════════════════════════╝

Please select an option:

  1) System Update (apt update & upgrade)
  2) Install Zsh (set as default shell)
  3) Install Oh-My-Zsh
  4) Install Powerlevel10k theme
  5) Deploy configuration files (.zshrc & .p10k.zsh)
  6) Install NVM (Node Version Manager)
  7) Install Node.js (via NVM)
  8) Install Claude CLI
  9) Install htop
  10) Configure UFW Firewall (SSH only)
  11) Configure SSH for Coolify
  12) Install Coolify
  13) Clean APT sources
  14) Run all steps
  15) Exit

Enter your choice [1-15]: 
```

### Run All Steps at Once

Select option 6 from the menu, or modify the script to run `run_all` function directly.

## Configuration Files

### .zshrc Configuration

The provided `.zshrc` includes:
- Powerlevel10k instant prompt initialization
- Oh-My-Zsh framework setup
- Plugin configuration (git, npm, zsh-autosuggestions, zsh-completions, zsh-syntax-highlighting)
- UTF-8 locale settings
- Useful aliases (e.g., `ll='ls -larth'`)
- Auto-update settings

### .p10k.zsh Configuration

The Powerlevel10k configuration includes:
- Rainbow color scheme with Unicode support
- Two-line prompt layout
- Git status integration
- Command execution time display
- Various development environment indicators
- 12-hour time format

## Backup and Recovery

All existing configuration files are automatically backed up to:
```
~/.config-backup-YYYYMMDD-HHMMSS/
```

To restore a backup:
```bash
cp ~/.config-backup-*/.zshrc ~/.zshrc
cp ~/.config-backup-*/.p10k.zsh ~/.p10k.zsh
```

## Security Considerations

### Firewall Configuration
The UFW firewall is configured with strict defaults:
- **Incoming**: Denied (except SSH)
- **Outgoing**: Allowed
- **SSH**: Port 22 (always allowed)
- **Coolify Ports** (if installed):
  - Port 80: HTTP
  - Port 443: HTTPS
  - Port 8000: Coolify Dashboard

### SSH Security
- Password authentication for root is disabled
- Only SSH key authentication is allowed for root
- ED25519 keys are generated for maximum security
- **Important**: Ensure you have SSH key access before enabling these settings

### Coolify Access
After Coolify installation:
- Dashboard: `http://your-server-ip:8000`
- Default credentials will be shown during installation
- Change default password immediately after first login

## Post-Installation

After installation:

1. **Log out and log back in** for shell changes to take effect
2. **Run `p10k configure`** to customize your Powerlevel10k theme (optional)
3. **Source the configuration** without logging out:
   ```bash
   source ~/.zshrc
   ```

## Troubleshooting

### Shell not changed
If the shell doesn't change after installation:
```bash
# Manually change shell
chsh -s $(which zsh)
# Log out and back in
```

### Theme not loading
Ensure the theme path is correct in `.zshrc`:
```bash
ZSH_THEME="powerlevel10k/powerlevel10k"
```

### Plugins not working
Verify plugins are installed in the correct directory:
```bash
ls ~/.oh-my-zsh/custom/plugins/
```

### Font issues
For the best experience with Powerlevel10k, install a Nerd Font:
- [Nerd Fonts Downloads](https://www.nerdfonts.com/font-downloads)
- Recommended: MesloLGS NF

## System Requirements

- **OS**: Ubuntu 20.04 LTS or newer
- **Memory**: 
  - Minimum 1GB RAM (without Coolify)
  - Minimum 2GB RAM (with Coolify)
- **Disk**: 
  - ~500MB for base installation
  - ~2GB+ for Coolify and Docker
- **Network**: Internet connection for package downloads
- **Ports**: SSH (22) must be accessible

## Security Notes

- The script requires sudo/root access
- Configuration files are set with secure permissions (644)
- Existing configurations are backed up before modification
- APT sources cleanup helps maintain system security

## Contributing

Feel free to submit issues and enhancement requests!

## License

This script is provided as-is for personal and commercial use.

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review the backup directory for original configurations
3. Reinstall specific components using the menu system

---

**Note**: Always review scripts before running them with sudo privileges. This script modifies system configurations and shell settings.