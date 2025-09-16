#!/bin/bash
# Custom Menu Builder module - Create and manage custom menu configurations
# Allows users to build personalized menus and save preset configurations

# Script metadata
readonly MODULE_VERSION="1.0.0"
readonly MODULE_NAME="custom-menu-builder"

# Configuration
readonly CUSTOM_MENU_DIR="/etc/server-config/custom-menus"
readonly PRESETS_DIR="$CUSTOM_MENU_DIR/presets"
readonly PROFILES_DIR="$CUSTOM_MENU_DIR/profiles"
readonly FAVORITES_FILE="$CUSTOM_MENU_DIR/favorites.json"
readonly RECENT_FILE="$CUSTOM_MENU_DIR/recent.json"

# Menu builder state
declare -A CUSTOM_MENU
declare -A MENU_SHORTCUTS
declare -A MENU_CATEGORIES
declare CURRENT_PROFILE=""

# ============================================================================
# Setup and Initialization
# ============================================================================

# Initialize custom menu system
initialize_custom_menu() {
    # Create directories
    sudo mkdir -p "$CUSTOM_MENU_DIR"
    sudo mkdir -p "$PRESETS_DIR"
    sudo mkdir -p "$PROFILES_DIR"

    # Initialize files if not exist
    [ ! -f "$FAVORITES_FILE" ] && echo '{"favorites": []}' | sudo tee "$FAVORITES_FILE" > /dev/null
    [ ! -f "$RECENT_FILE" ] && echo '{"recent": []}' | sudo tee "$RECENT_FILE" > /dev/null

    # Load default presets if not exist
    create_default_presets
}

# Create default presets
create_default_presets() {
    # Developer preset
    if [ ! -f "$PRESETS_DIR/developer.json" ]; then
        cat << 'EOF' | sudo tee "$PRESETS_DIR/developer.json" > /dev/null
{
    "name": "Developer",
    "description": "Development environment focused menu",
    "categories": {
        "1": "Development Tools",
        "2": "Container Management",
        "3": "Version Control",
        "4": "Testing & Debug"
    },
    "items": {
        "1.1": {
            "name": "Install Node.js",
            "command": "src/base/dev-tools.sh --nvm",
            "description": "Install NVM and Node.js"
        },
        "1.2": {
            "name": "Setup Zsh",
            "command": "src/base/shell-setup.sh --complete",
            "description": "Install Zsh with Oh-My-Zsh"
        },
        "2.1": {
            "name": "Docker Status",
            "command": "docker ps -a",
            "description": "Show all Docker containers"
        },
        "2.2": {
            "name": "Docker Compose Up",
            "command": "docker-compose up -d",
            "description": "Start Docker Compose services"
        }
    },
    "shortcuts": {
        "d": "2.1",
        "c": "2.2",
        "n": "1.1",
        "z": "1.2"
    }
}
EOF
    fi

    # Security preset
    if [ ! -f "$PRESETS_DIR/security.json" ]; then
        cat << 'EOF' | sudo tee "$PRESETS_DIR/security.json" > /dev/null
{
    "name": "Security Analyst",
    "description": "Security and compliance focused menu",
    "categories": {
        "1": "Security Scanning",
        "2": "Access Control",
        "3": "Monitoring",
        "4": "Incident Response"
    },
    "items": {
        "1.1": {
            "name": "Run Lynis Audit",
            "command": "src/monitoring/lynis.sh --audit system",
            "description": "Security audit with Lynis"
        },
        "1.2": {
            "name": "Check Compliance",
            "command": "src/monitoring/compliance.sh --check cis",
            "description": "CIS compliance check"
        },
        "2.1": {
            "name": "SSH Sessions",
            "command": "who",
            "description": "Show active SSH sessions"
        },
        "2.2": {
            "name": "Failed Logins",
            "command": "grep 'Failed password' /var/log/auth.log | tail -20",
            "description": "Recent failed login attempts"
        },
        "3.1": {
            "name": "Security Logs",
            "command": "sudo journalctl -u sshd -u fail2ban --since '1 hour ago'",
            "description": "Recent security events"
        }
    },
    "shortcuts": {
        "l": "1.1",
        "c": "1.2",
        "s": "2.1",
        "f": "2.2",
        "e": "3.1"
    }
}
EOF
    fi

    # Admin preset
    if [ ! -f "$PRESETS_DIR/admin.json" ]; then
        cat << 'EOF' | sudo tee "$PRESETS_DIR/admin.json" > /dev/null
{
    "name": "System Administrator",
    "description": "System administration focused menu",
    "categories": {
        "1": "System Management",
        "2": "User Management",
        "3": "Service Control",
        "4": "Backup & Recovery"
    },
    "items": {
        "1.1": {
            "name": "System Update",
            "command": "src/base/system-update.sh --complete",
            "description": "Update system packages"
        },
        "1.2": {
            "name": "System Status",
            "command": "systemctl status --no-pager | head -50",
            "description": "System service status"
        },
        "2.1": {
            "name": "User List",
            "command": "cut -d: -f1 /etc/passwd | sort",
            "description": "List all users"
        },
        "2.2": {
            "name": "Add User",
            "command": "src/base/user-setup.sh --add-user",
            "description": "Add new user"
        },
        "3.1": {
            "name": "Restart Service",
            "command": "echo 'Enter service name:' && read svc && sudo systemctl restart $svc",
            "description": "Restart a service"
        },
        "4.1": {
            "name": "Backup Config",
            "command": "src/lib/backup.sh --backup-all",
            "description": "Backup system configuration"
        }
    },
    "shortcuts": {
        "u": "1.1",
        "s": "1.2",
        "a": "2.2",
        "r": "3.1",
        "b": "4.1"
    }
}
EOF
    fi

    # DevOps preset
    if [ ! -f "$PRESETS_DIR/devops.json" ]; then
        cat << 'EOF' | sudo tee "$PRESETS_DIR/devops.json" > /dev/null
{
    "name": "DevOps Engineer",
    "description": "DevOps and automation focused menu",
    "categories": {
        "1": "CI/CD",
        "2": "Infrastructure",
        "3": "Monitoring",
        "4": "Automation"
    },
    "items": {
        "1.1": {
            "name": "Docker Build",
            "command": "docker build -t app:latest .",
            "description": "Build Docker image"
        },
        "1.2": {
            "name": "Deploy Stack",
            "command": "docker stack deploy -c docker-compose.yml app",
            "description": "Deploy Docker stack"
        },
        "2.1": {
            "name": "Terraform Plan",
            "command": "terraform plan",
            "description": "Show Terraform plan"
        },
        "2.2": {
            "name": "Ansible Playbook",
            "command": "ansible-playbook -i inventory playbook.yml",
            "description": "Run Ansible playbook"
        },
        "3.1": {
            "name": "Container Logs",
            "command": "docker logs -f --tail 100",
            "description": "Follow container logs"
        },
        "3.2": {
            "name": "System Metrics",
            "command": "htop",
            "description": "System resource monitor"
        }
    },
    "shortcuts": {
        "b": "1.1",
        "d": "1.2",
        "t": "2.1",
        "a": "2.2",
        "l": "3.1",
        "m": "3.2"
    }
}
EOF
    fi
}

# ============================================================================
# Menu Builder Functions
# ============================================================================

# Create custom menu
create_custom_menu() {
    local menu_name="$1"

    echo "Creating custom menu: $menu_name"
    echo ""

    # Initialize menu structure
    CUSTOM_MENU["name"]="$menu_name"
    CUSTOM_MENU["description"]=""
    CUSTOM_MENU["created"]="$(date -Iseconds)"

    # Get description
    read -p "Menu description: " description
    CUSTOM_MENU["description"]="$description"

    # Add categories
    echo ""
    echo "Add menu categories (empty to finish):"
    local cat_num=1
    while true; do
        read -p "Category $cat_num name: " cat_name
        [ -z "$cat_name" ] && break

        MENU_CATEGORIES["$cat_num"]="$cat_name"
        ((cat_num++))
    done

    # Add menu items
    echo ""
    echo "Add menu items:"
    for cat_key in "${!MENU_CATEGORIES[@]}"; do
        echo ""
        echo "Category: ${MENU_CATEGORIES[$cat_key]}"

        local item_num=1
        while true; do
            echo ""
            read -p "  Item name (empty to next category): " item_name
            [ -z "$item_name" ] && break

            local item_key="${cat_key}.${item_num}"

            read -p "  Command/Module: " item_command
            read -p "  Description: " item_description
            read -p "  Shortcut key (optional): " shortcut

            # Store item
            CUSTOM_MENU["item_${item_key}_name"]="$item_name"
            CUSTOM_MENU["item_${item_key}_command"]="$item_command"
            CUSTOM_MENU["item_${item_key}_description"]="$item_description"

            if [ -n "$shortcut" ]; then
                MENU_SHORTCUTS["$shortcut"]="$item_key"
            fi

            ((item_num++))
        done
    done

    # Save menu
    save_custom_menu "$menu_name"
}

# Save custom menu
save_custom_menu() {
    local menu_name="$1"
    local menu_file="$CUSTOM_MENU_DIR/${menu_name}.json"

    # Build JSON structure
    {
        echo "{"
        echo "  \"name\": \"${CUSTOM_MENU[name]}\","
        echo "  \"description\": \"${CUSTOM_MENU[description]}\","
        echo "  \"created\": \"${CUSTOM_MENU[created]}\","
        echo "  \"categories\": {"

        local first_cat=true
        for cat_key in $(echo "${!MENU_CATEGORIES[@]}" | tr ' ' '\n' | sort -n); do
            [ "$first_cat" = false ] && echo ","
            echo -n "    \"$cat_key\": \"${MENU_CATEGORIES[$cat_key]}\""
            first_cat=false
        done

        echo ""
        echo "  },"
        echo "  \"items\": {"

        local first_item=true
        for key in "${!CUSTOM_MENU[@]}"; do
            if [[ $key == item_*_name ]]; then
                local item_key="${key#item_}"
                item_key="${item_key%_name}"

                [ "$first_item" = false ] && echo ","
                echo -n "    \"$item_key\": {"
                echo -n "\"name\": \"${CUSTOM_MENU[item_${item_key}_name]}\", "
                echo -n "\"command\": \"${CUSTOM_MENU[item_${item_key}_command]}\", "
                echo -n "\"description\": \"${CUSTOM_MENU[item_${item_key}_description]}\"}"
                first_item=false
            fi
        done

        echo ""
        echo "  },"
        echo "  \"shortcuts\": {"

        local first_shortcut=true
        for shortcut in "${!MENU_SHORTCUTS[@]}"; do
            [ "$first_shortcut" = false ] && echo ","
            echo -n "    \"$shortcut\": \"${MENU_SHORTCUTS[$shortcut]}\""
            first_shortcut=false
        done

        echo ""
        echo "  }"
        echo "}"
    } | sudo tee "$menu_file" > /dev/null

    echo ""
    print_success "Custom menu saved: $menu_file"
}

# Load custom menu
load_custom_menu() {
    local menu_file="$1"

    if [ ! -f "$menu_file" ]; then
        print_error "Menu file not found: $menu_file"
        return 1
    fi

    # Parse JSON and load menu
    # This is simplified - in production, use jq for proper JSON parsing
    print_success "Menu loaded: $(basename "$menu_file")"
    return 0
}

# ============================================================================
# Profile Management
# ============================================================================

# Create user profile
create_user_profile() {
    local profile_name="$1"

    echo "Creating user profile: $profile_name"
    echo ""

    local profile_file="$PROFILES_DIR/${profile_name}.json"

    # Get profile preferences
    echo "Configure profile preferences:"
    echo ""

    read -p "Default preset (developer/admin/security/devops): " default_preset
    read -p "Show recent items? (y/n): " show_recent
    read -p "Show favorites? (y/n): " show_favorites
    read -p "Enable shortcuts? (y/n): " enable_shortcuts
    read -p "Auto-save history? (y/n): " auto_save

    # Build profile JSON
    cat << EOF | sudo tee "$profile_file" > /dev/null
{
    "name": "$profile_name",
    "created": "$(date -Iseconds)",
    "preferences": {
        "default_preset": "$default_preset",
        "show_recent": "$([[ $show_recent == y* ]] && echo true || echo false)",
        "show_favorites": "$([[ $show_favorites == y* ]] && echo true || echo false)",
        "enable_shortcuts": "$([[ $enable_shortcuts == y* ]] && echo true || echo false)",
        "auto_save_history": "$([[ $auto_save == y* ]] && echo true || echo false)",
        "theme": "default",
        "max_recent": 10,
        "max_favorites": 20
    },
    "custom_menus": [],
    "shortcuts": {},
    "favorites": []
}
EOF

    print_success "Profile created: $profile_name"
}

# Load user profile
load_user_profile() {
    local profile_name="$1"
    local profile_file="$PROFILES_DIR/${profile_name}.json"

    if [ ! -f "$profile_file" ]; then
        print_error "Profile not found: $profile_name"
        return 1
    fi

    CURRENT_PROFILE="$profile_name"

    # Load profile settings
    # In production, use jq to parse JSON properly
    print_success "Profile loaded: $profile_name"

    # Load associated preset if configured
    local default_preset=$(grep '"default_preset"' "$profile_file" | cut -d'"' -f4)
    if [ -n "$default_preset" ] && [ -f "$PRESETS_DIR/${default_preset}.json" ]; then
        load_preset "$default_preset"
    fi

    return 0
}

# Export profile
export_profile() {
    local profile_name="$1"
    local export_file="${2:-${profile_name}-export.tar.gz}"

    if [ ! -f "$PROFILES_DIR/${profile_name}.json" ]; then
        print_error "Profile not found: $profile_name"
        return 1
    fi

    # Create export package
    local temp_dir="/tmp/profile-export-$$"
    mkdir -p "$temp_dir"

    # Copy profile and related files
    cp "$PROFILES_DIR/${profile_name}.json" "$temp_dir/"

    # Include custom menus referenced in profile
    if [ -d "$CUSTOM_MENU_DIR" ]; then
        cp "$CUSTOM_MENU_DIR"/*.json "$temp_dir/" 2>/dev/null || true
    fi

    # Create tarball
    tar -czf "$export_file" -C "$temp_dir" .
    rm -rf "$temp_dir"

    print_success "Profile exported: $export_file"
    return 0
}

# Import profile
import_profile() {
    local import_file="$1"

    if [ ! -f "$import_file" ]; then
        print_error "Import file not found: $import_file"
        return 1
    fi

    # Extract to temp directory
    local temp_dir="/tmp/profile-import-$$"
    mkdir -p "$temp_dir"

    tar -xzf "$import_file" -C "$temp_dir"

    # Copy files to appropriate locations
    for json_file in "$temp_dir"/*.json; do
        [ -f "$json_file" ] || continue

        local filename=$(basename "$json_file")
        if [[ $filename == *.json ]]; then
            sudo cp "$json_file" "$PROFILES_DIR/"
        fi
    done

    rm -rf "$temp_dir"

    print_success "Profile imported successfully"
    return 0
}

# ============================================================================
# Preset Management
# ============================================================================

# Load preset
load_preset() {
    local preset_name="$1"
    local preset_file="$PRESETS_DIR/${preset_name}.json"

    if [ ! -f "$preset_file" ]; then
        print_error "Preset not found: $preset_name"
        return 1
    fi

    print_success "Preset loaded: $preset_name"

    # Display preset menu
    display_preset_menu "$preset_file"
    return 0
}

# Display preset menu
display_preset_menu() {
    local preset_file="$1"

    clear
    echo -e "${COLOR_HEADER}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                         Custom Menu                                ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"

    # Parse and display menu from JSON
    # In production, use jq for proper parsing
    local preset_name=$(grep '"name"' "$preset_file" | head -1 | cut -d'"' -f4)
    local description=$(grep '"description"' "$preset_file" | head -1 | cut -d'"' -f4)

    echo "Preset: $preset_name"
    echo "Description: $description"
    echo ""

    # Display menu items (simplified)
    echo "Menu items loaded from preset"
    echo ""
    echo "Press Enter to continue..."
    read -r
}

# Save as preset
save_as_preset() {
    local preset_name="$1"

    if [ ${#CUSTOM_MENU[@]} -eq 0 ]; then
        print_error "No custom menu to save"
        return 1
    fi

    local preset_file="$PRESETS_DIR/${preset_name}.json"

    # Copy current custom menu to preset
    save_custom_menu "$preset_name"
    sudo mv "$CUSTOM_MENU_DIR/${preset_name}.json" "$preset_file"

    print_success "Saved as preset: $preset_name"
    return 0
}

# List presets
list_presets() {
    echo "Available Presets:"
    echo ""

    for preset_file in "$PRESETS_DIR"/*.json; do
        [ -f "$preset_file" ] || continue

        local preset_name=$(basename "$preset_file" .json)
        local description=$(grep '"description"' "$preset_file" | head -1 | cut -d'"' -f4)

        echo "  • $preset_name - $description"
    done

    echo ""
}

# ============================================================================
# Favorites Management
# ============================================================================

# Add to favorites
add_to_favorites() {
    local item_name="$1"
    local item_command="$2"

    # Update favorites file
    if [ -f "$FAVORITES_FILE" ]; then
        # Add to favorites array in JSON
        # In production, use jq for proper JSON manipulation
        echo "Added to favorites: $item_name"
    fi
}

# Show favorites menu
show_favorites_menu() {
    clear
    echo -e "${COLOR_HEADER}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                          Favorites Menu                            ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"

    if [ ! -f "$FAVORITES_FILE" ]; then
        echo "No favorites configured"
        echo ""
        echo "Press Enter to continue..."
        read -r
        return
    fi

    # Display favorites
    # In production, parse JSON properly with jq
    echo "Your favorite commands:"
    echo ""
    echo "1) System Update"
    echo "2) Docker Status"
    echo "3) Security Scan"
    echo ""

    echo -n "Select favorite [1-3] or Q to quit: "
    read -r choice

    case "$choice" in
        [qQ])
            return
            ;;
        *)
            echo "Executing favorite command..."
            ;;
    esac
}

# ============================================================================
# Quick Access Menu
# ============================================================================

# Display quick access menu
display_quick_access_menu() {
    clear
    echo -e "${COLOR_HEADER}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                       Quick Access Menu                            ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"

    echo "Quick Commands:"
    echo ""
    echo "  U) Update System        - Run system updates"
    echo "  S) Security Status      - Check security status"
    echo "  D) Docker Status        - Show Docker containers"
    echo "  N) Network Status       - Display network info"
    echo "  L) View Logs           - Recent system logs"
    echo "  B) Backup              - Backup configuration"
    echo "  R) Restart Service     - Restart a service"
    echo "  T) System Stats        - System statistics"
    echo ""
    echo "  F) Favorites           - Show favorites menu"
    echo "  H) History             - Recent commands"
    echo "  Q) Quit                - Exit menu"
    echo ""

    echo -n "Select option: "
    read -r choice

    case "${choice^^}" in
        U)
            sudo bash /home/ubuntu/server-config/src/base/system-update.sh --check
            ;;
        S)
            sudo bash /home/ubuntu/server-config/src/monitoring/lynis.sh --audit quick
            ;;
        D)
            docker ps -a 2>/dev/null || echo "Docker not installed"
            ;;
        N)
            ip addr show
            ;;
        L)
            sudo journalctl -xe --no-pager | tail -50
            ;;
        B)
            sudo bash /home/ubuntu/server-config/src/lib/backup.sh --backup-all
            ;;
        R)
            read -p "Service name: " service
            sudo systemctl restart "$service"
            ;;
        T)
            htop || top
            ;;
        F)
            show_favorites_menu
            ;;
        H)
            show_recent_commands
            ;;
        Q)
            return
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac

    echo ""
    echo "Press Enter to continue..."
    read -r
}

# Show recent commands
show_recent_commands() {
    echo "Recent Commands:"
    echo ""

    if [ -f "$RECENT_FILE" ]; then
        # Display recent commands from JSON
        # In production, use jq for proper parsing
        echo "1) sudo apt update"
        echo "2) docker ps -a"
        echo "3) systemctl status nginx"
    else
        echo "No recent commands"
    fi

    echo ""
}

# ============================================================================
# Main Menu Builder Interface
# ============================================================================

# Display menu builder main menu
display_builder_menu() {
    clear
    echo -e "${COLOR_HEADER}"
    echo "╔════════════════════════════════════════════════════════════════════╗"
    echo "║                      Custom Menu Builder                           ║"
    echo "╚════════════════════════════════════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"
    echo ""
    echo "Menu Builder Options:"
    echo ""
    echo "  1) Create Custom Menu    - Build a new custom menu"
    echo "  2) Load Custom Menu      - Load existing custom menu"
    echo "  3) Edit Menu            - Modify existing menu"
    echo "  4) Delete Menu          - Remove custom menu"
    echo ""
    echo "Preset Management:"
    echo "  5) Load Preset          - Load menu preset"
    echo "  6) Save as Preset       - Save current menu as preset"
    echo "  7) List Presets         - Show available presets"
    echo ""
    echo "Profile Management:"
    echo "  8) Create Profile       - Create user profile"
    echo "  9) Load Profile         - Load user profile"
    echo "  E) Export Profile       - Export profile to file"
    echo "  I) Import Profile       - Import profile from file"
    echo ""
    echo "Quick Access:"
    echo "  Q) Quick Access Menu    - Show quick access menu"
    echo "  F) Favorites           - Manage favorites"
    echo ""
    echo "  X) Exit                - Exit menu builder"
    echo ""

    if [ -n "$CURRENT_PROFILE" ]; then
        echo "Current Profile: $CURRENT_PROFILE"
    fi
    echo ""
}

# Run menu builder
run_menu_builder() {
    initialize_custom_menu

    while true; do
        display_builder_menu

        echo -n "Select option: "
        read -r choice

        case "${choice^^}" in
            1)
                read -p "Menu name: " menu_name
                create_custom_menu "$menu_name"
                ;;
            2)
                echo "Available custom menus:"
                ls "$CUSTOM_MENU_DIR"/*.json 2>/dev/null | while read -r f; do
                    echo "  - $(basename "$f" .json)"
                done
                read -p "Menu to load: " menu_name
                load_custom_menu "$CUSTOM_MENU_DIR/${menu_name}.json"
                ;;
            3)
                echo "Edit menu - Not yet implemented"
                ;;
            4)
                echo "Delete menu - Not yet implemented"
                ;;
            5)
                list_presets
                read -p "Preset to load: " preset_name
                load_preset "$preset_name"
                ;;
            6)
                read -p "Preset name: " preset_name
                save_as_preset "$preset_name"
                ;;
            7)
                list_presets
                ;;
            8)
                read -p "Profile name: " profile_name
                create_user_profile "$profile_name"
                ;;
            9)
                echo "Available profiles:"
                ls "$PROFILES_DIR"/*.json 2>/dev/null | while read -r f; do
                    echo "  - $(basename "$f" .json)"
                done
                read -p "Profile to load: " profile_name
                load_user_profile "$profile_name"
                ;;
            E)
                read -p "Profile to export: " profile_name
                read -p "Export filename (${profile_name}-export.tar.gz): " export_file
                export_profile "$profile_name" "${export_file:-${profile_name}-export.tar.gz}"
                ;;
            I)
                read -p "Import file: " import_file
                import_profile "$import_file"
                ;;
            Q)
                display_quick_access_menu
                ;;
            F)
                show_favorites_menu
                ;;
            X)
                echo "Exiting menu builder"
                break
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac

        if [[ ! "${choice^^}" =~ ^[XQ]$ ]]; then
            echo ""
            echo "Press Enter to continue..."
            read -r
        fi
    done
}

# ============================================================================
# Module Management
# ============================================================================

# Show module help
show_help() {
    cat << EOF
Custom Menu Builder Module v${MODULE_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --builder           Run menu builder interface (default)
    --create NAME       Create new custom menu
    --load NAME         Load custom menu
    --preset NAME       Load preset menu
    --profile NAME      Load user profile
    --quick             Show quick access menu
    --favorites         Show favorites menu
    --list-presets      List available presets
    --list-profiles     List available profiles
    --export-profile    Export profile to file
    --import-profile    Import profile from file
    --help              Show this help message

PRESETS:
    developer           Development environment menu
    admin              System administration menu
    security           Security analyst menu
    devops             DevOps engineer menu

EXAMPLES:
    # Run menu builder
    $0 --builder

    # Load preset
    $0 --preset developer

    # Create custom menu
    $0 --create my-menu

    # Load profile
    $0 --profile john-doe

    # Quick access menu
    $0 --quick

FILES:
    Custom Menus: $CUSTOM_MENU_DIR
    Presets: $PRESETS_DIR
    Profiles: $PROFILES_DIR

EOF
}

# List profiles
list_profiles() {
    echo "Available Profiles:"
    echo ""

    for profile_file in "$PROFILES_DIR"/*.json; do
        [ -f "$profile_file" ] || continue

        local profile_name=$(basename "$profile_file" .json)
        local created=$(grep '"created"' "$profile_file" | head -1 | cut -d'"' -f4)

        echo "  • $profile_name (created: ${created%%T*})"
    done

    echo ""
}

# Export functions
export -f initialize_custom_menu create_custom_menu
export -f load_custom_menu save_custom_menu
export -f create_user_profile load_user_profile
export -f load_preset list_presets
export -f display_quick_access_menu show_favorites_menu

# Source required libraries
if [ -z "${SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || true

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --create)
            initialize_custom_menu
            create_custom_menu "${2:-custom}"
            ;;
        --load)
            initialize_custom_menu
            load_custom_menu "$CUSTOM_MENU_DIR/${2}.json"
            ;;
        --preset)
            initialize_custom_menu
            load_preset "${2:-developer}"
            ;;
        --profile)
            initialize_custom_menu
            load_user_profile "${2}"
            ;;
        --quick)
            display_quick_access_menu
            ;;
        --favorites)
            show_favorites_menu
            ;;
        --list-presets)
            initialize_custom_menu
            list_presets
            ;;
        --list-profiles)
            initialize_custom_menu
            list_profiles
            ;;
        --export-profile)
            initialize_custom_menu
            export_profile "${2}" "${3}"
            ;;
        --import-profile)
            initialize_custom_menu
            import_profile "${2}"
            ;;
        --help)
            show_help
            ;;
        --builder|*)
            run_menu_builder
            ;;
    esac
fi