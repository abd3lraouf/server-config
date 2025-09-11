# Ubuntu Server Setup Script

A comprehensive setup script for configuring Ubuntu Server with Zsh, Oh-My-Zsh, Powerlevel10k theme, and essential plugins.

## Features

- 🚀 **Interactive Menu System** - Choose which components to install
- 🎨 **Powerlevel10k Theme** - Beautiful and fast Zsh theme
- 🔌 **Essential Plugins** - Auto-suggestions, syntax highlighting, and completions
- 👥 **Multi-User Support** - Configures both root and main user
- 💾 **Automatic Backups** - Backs up existing configurations before changes
- 🧹 **APT Sources Cleanup** - Removes duplicate and obsolete APT sources

## Quick Start (One-liner)

Clone and run directly from GitHub:

```bash
git clone https://github.com/abd3lraouf/server-config.git && cd server-config && chmod +x setup.sh && sudo ./setup.sh
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

### 1. Install Zsh
- Installs Zsh package
- Sets Zsh as default shell for root and main user
- Automatically detects the main non-root user

### 2. Install Oh-My-Zsh
- Downloads and installs Oh-My-Zsh framework
- Installs three essential plugins:
  - **zsh-autosuggestions** - Fish-like autosuggestions
  - **zsh-completions** - Additional completion definitions
  - **zsh-syntax-highlighting** - Fish shell-like syntax highlighting

### 3. Install Powerlevel10k
- Clones the Powerlevel10k repository
- Sets up the theme for both root and main user
- Provides a beautiful, customizable prompt

### 4. Deploy Configuration Files
- Copies `.zshrc` to user home directories
- Copies `.p10k.zsh` configuration
- Maintains proper file permissions and ownership
- Creates backups of existing configurations

### 5. Clean APT Sources
- Installs `python3-apt` dependency
- Downloads `aptsources-cleanup.pyz` if not present
- Removes duplicate and obsolete APT sources
- Helps maintain a clean package management system

### 6. Run All Steps
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

  1) Install Zsh (set as default shell)
  2) Install Oh-My-Zsh
  3) Install Powerlevel10k theme
  4) Deploy configuration files (.zshrc & .p10k.zsh)
  5) Clean APT sources
  6) Run all steps
  7) Exit

Enter your choice [1-7]: 
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
- **Memory**: Minimum 512MB RAM
- **Disk**: ~100MB free space
- **Network**: Internet connection for package downloads

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