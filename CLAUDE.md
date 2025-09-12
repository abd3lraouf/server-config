# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is an Ubuntu server configuration repository containing a bash script (`setup.sh`) that automates server setup with Zsh, development tools, and security configurations. The script is designed to be run on Ubuntu 20.04+ servers with root/sudo access.

## Key Commands

### Running the Setup Script

**Interactive mode (presents menu):**
```bash
sudo ./setup.sh
```

**Run specific menu options non-interactively:**
```bash
# Run all base configuration steps
sudo bash -c './setup.sh <<< "1\n12"'

# Run basic security configuration
sudo bash -c './setup.sh <<< "2\n3"'

# Run complete Zero Trust setup
sudo bash -c './setup.sh <<< "2\n11"'

# Run everything (base + security)
sudo bash -c './setup.sh <<< "3"'
```

**Zero Trust setup with parameters:**
```bash
# Set environment variables for non-interactive setup
export EMAIL="admin@example.com"
export CLOUDFLARE_TOKEN="your-token"
export DOMAIN="example.com"
export TAILSCALE_KEY="your-auth-key"
sudo -E ./setup.sh
```

### Testing Changes

When modifying `setup.sh`:
- Test functions individually by calling them directly after sourcing the script
- Use shellcheck for bash script validation: `shellcheck setup.sh`
- Test on a fresh Ubuntu VM/container before deploying

## Architecture

The `setup.sh` script follows a modular architecture:

1. **Menu System**: Interactive menu with numbered options organized into:
   - Base Configuration (system updates, shell setup, development tools)
   - Security Configuration (basic security + comprehensive Zero Trust options)
   - Run All Steps option

2. **Function Organization**: Each installation/configuration task is a separate function that:
   - Checks if the component is already installed/configured
   - Creates backups of existing configurations
   - Handles both root and non-root user configurations
   - Reports status with colored output functions

3. **Zero Trust Security Architecture**:
   - **System Hardening**: PAM policies, AppArmor, kernel parameters, automatic updates
   - **Network Security**: UFW-Docker integration, Tailscale for secure access
   - **Application Security**: Cloudflare Tunnel, CrowdSec protection, Traefik security middleware
   - **Monitoring**: Lynis auditing, AIDE file integrity, Logwatch analysis
   - **Validation**: Comprehensive security validation and reporting

4. **User Detection**: Automatically detects the main non-root user for user-specific configurations (like shell changes)

5. **Backup Strategy**: 
   - System configs backed up to `~/.config-backup-YYYYMMDD-HHMMSS/`
   - Zero Trust configs backed up to `/etc/zero-trust/backups/`

## Required Files

The repository must contain these configuration files:
- `setup.sh` - Main installation script
- `zshrc` - Zsh configuration to be copied to user's home
- `p10k.zsh` - Powerlevel10k theme configuration

## Development Considerations

- The script uses `set -e` to exit on errors - ensure error handling in new functions
- Functions should use the print_status/print_success/print_error/print_warning helpers for consistent output
- When adding new menu items, update both the menu display and the case statement
- Security-related changes should maintain Coolify compatibility (specific SSH and firewall requirements)
- All user-specific configurations must handle both root and the detected main user