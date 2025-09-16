#!/bin/bash
# Validation functions for input sanitization and security
# This library provides comprehensive validation for all user inputs

# Library metadata
[[ -z "${LIB_VALIDATION_VERSION:-}" ]] && readonly LIB_VALIDATION_VERSION="1.0.0"
[[ -z "${LIB_VALIDATION_NAME:-}" ]] && readonly LIB_VALIDATION_NAME="validation"

# ============================================================================
# Email Validation
# ============================================================================

# Validate email address format
validate_email() {
    local email="$1"
    local email_regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

    # Check if empty
    if [ -z "$email" ]; then
        return 1
    fi

    # Check format
    if ! [[ "$email" =~ $email_regex ]]; then
        return 1
    fi

    # Check length (max 254 chars per RFC)
    if [ ${#email} -gt 254 ]; then
        return 1
    fi

    # Check for dangerous characters
    if echo "$email" | grep -qE '[;|&$`(){}\[\]<>]'; then
        return 1
    fi

    return 0
}

# ============================================================================
# Domain Validation
# ============================================================================

# Validate domain name format
validate_domain() {
    local domain="$1"
    # Allow subdomain.example.com or example.com format
    local domain_regex='^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$'

    # Check if empty
    if [ -z "$domain" ]; then
        return 1
    fi

    # Check format
    if ! [[ "$domain" =~ $domain_regex ]]; then
        return 1
    fi

    # Check length (max 253 chars)
    if [ ${#domain} -gt 253 ]; then
        return 1
    fi

    # Check for dangerous characters
    if echo "$domain" | grep -qE "[;|&$\`(){}\[\]<>'\"\\\\]"; then
        return 1
    fi

    return 0
}

# ============================================================================
# Token/API Key Validation
# ============================================================================

# Validate token/API key format
validate_token() {
    local token="$1"
    local max_length="${2:-2000}"

    # Check if empty
    if [ -z "$token" ]; then
        return 1
    fi

    # Check length
    if [ ${#token} -gt $max_length ]; then
        return 1
    fi

    # Allow only safe characters for tokens (base64 and JWT common chars)
    if ! [[ "$token" =~ ^[A-Za-z0-9_=./-]+$ ]]; then
        return 1
    fi

    # Check for script output contamination
    if echo "$token" | grep -qE '(PHASE|INFO|WARNING|ERROR|\[.*\]|▶|→)'; then
        return 1
    fi

    return 0
}

# ============================================================================
# User/System Validation
# ============================================================================

# Validate Linux username
validate_username() {
    local username="$1"

    # Check if empty
    if [ -z "$username" ]; then
        return 1
    fi

    # Check format (Linux username rules)
    if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        return 1
    fi

    # Check if user exists
    if ! id "$username" &>/dev/null; then
        return 1
    fi

    return 0
}

# ============================================================================
# Name Validation
# ============================================================================

# Validate tunnel/service names
validate_name() {
    local name="$1"
    local max_length="${2:-63}"

    # Check if empty
    if [ -z "$name" ]; then
        return 1
    fi

    # Allow alphanumeric, dash, underscore, and dot
    if ! [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,61}[a-zA-Z0-9]$ ]]; then
        # Also allow single word names
        if ! [[ "$name" =~ ^[a-zA-Z0-9]+$ ]]; then
            return 1
        fi
    fi

    # Check length
    if [ ${#name} -gt $max_length ]; then
        return 1
    fi

    # Check for dangerous characters
    if echo "$name" | grep -qE "[;|&$\`(){}\[\]<>'\"\\\\]"; then
        return 1
    fi

    return 0
}

# Validate Tailscale tag name
validate_tag() {
    local tag="$1"

    # Check if empty (tags are optional)
    if [ -z "$tag" ]; then
        return 0
    fi

    # Remove 'tag:' prefix if present for validation
    tag="${tag#tag:}"

    # Tag must be alphanumeric with optional dashes
    if ! [[ "$tag" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$ ]]; then
        # Also allow single word tags
        if ! [[ "$tag" =~ ^[a-zA-Z0-9]+$ ]]; then
            return 1
        fi
    fi

    return 0
}

# ============================================================================
# Input Validation
# ============================================================================

# Validate menu choice
validate_menu_choice() {
    local choice="$1"
    local min="$2"
    local max="$3"

    # Check if empty
    if [ -z "$choice" ]; then
        return 1
    fi

    # Check if numeric
    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # Check range
    if [ "$choice" -lt "$min" ] || [ "$choice" -gt "$max" ]; then
        return 1
    fi

    return 0
}

# Validate yes/no input
validate_yes_no() {
    local input="$1"

    if [[ "$input" =~ ^[YyNn]$ ]]; then
        return 0
    fi

    return 1
}

# Validate confirmation input
validate_confirmation() {
    local input="$1"
    local expected="$2"

    if [ "$input" = "$expected" ]; then
        return 0
    fi

    return 1
}

# ============================================================================
# Sanitization Functions
# ============================================================================

# Sanitize input for use in commands
sanitize_for_command() {
    local input="$1"
    # Remove or escape potentially dangerous characters
    echo "$input" | sed 's/[;|&$`(){}\[\]<>]//g' | tr -d '\n\r'
}

# Sanitize input for use in filenames
sanitize_for_file() {
    local input="$1"
    # Keep only alphanumeric, dash, underscore, and dot
    echo "$input" | sed 's/[^a-zA-Z0-9._-]//g'
}

# ============================================================================
# System Validation
# ============================================================================

# Validate Ubuntu version
validate_ubuntu_version() {
    local required_version="${1:-24.04}"
    local current_version

    print_status "Validating Ubuntu version..."

    # Check if we're on Ubuntu
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot detect OS version"
        return 1
    fi

    if ! grep -q "Ubuntu" /etc/os-release; then
        print_error "This script is designed for Ubuntu systems only"
        return 1
    fi

    # Get version
    current_version=$(lsb_release -rs 2>/dev/null || grep VERSION_ID /etc/os-release | cut -d'"' -f2)

    # Compare versions
    if [[ "$current_version" != "$required_version" ]]; then
        print_warning "This script is optimized for Ubuntu $required_version"
        print_warning "Current version: Ubuntu $current_version"

        if [[ "${SKIP_VALIDATION}" != true ]]; then
            echo -ne "${YELLOW}Continue anyway? [y/N]: ${NC}"
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                print_error "Ubuntu version validation failed"
                return 1
            fi
        fi
    fi

    print_success "Ubuntu version $current_version validated"
    return 0
}

# ============================================================================
# Network Validation
# ============================================================================

# Validate IP address format
validate_ip() {
    local ip="$1"
    local ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

    if ! [[ "$ip" =~ $ip_regex ]]; then
        return 1
    fi

    # Check each octet
    IFS='.' read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [ "$octet" -gt 255 ]; then
            return 1
        fi
    done

    return 0
}

# Validate port number
validate_port() {
    local port="$1"

    # Check if numeric
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # Check range (1-65535)
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi

    return 0
}

# Validate URL format
validate_url() {
    local url="$1"
    local url_regex='^https?://[a-zA-Z0-9.-]+(\.[a-zA-Z]{2,})(:[0-9]+)?(/.*)?$'

    if [[ "$url" =~ $url_regex ]]; then
        return 0
    fi

    return 1
}

# ============================================================================
# File/Path Validation
# ============================================================================

# Validate file path (basic security check)
validate_path() {
    local path="$1"

    # Check for path traversal attempts
    if echo "$path" | grep -qE '\.\./|/\.\.'; then
        return 1
    fi

    # Check for dangerous characters
    if echo "$path" | grep -qE '[;|&$`(){}]'; then
        return 1
    fi

    return 0
}

# Check if file exists and is readable
validate_file_exists() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 1
    fi

    if [ ! -r "$file" ]; then
        return 1
    fi

    return 0
}

# Check if directory exists and is writable
validate_directory_writable() {
    local dir="$1"

    if [ ! -d "$dir" ]; then
        return 1
    fi

    if [ ! -w "$dir" ]; then
        return 1
    fi

    return 0
}

# Export all validation functions
export -f validate_email validate_domain validate_token validate_username
export -f validate_name validate_tag validate_menu_choice validate_yes_no
export -f validate_confirmation sanitize_for_command sanitize_for_file
export -f validate_ubuntu_version validate_ip validate_port validate_url
export -f validate_path validate_file_exists validate_directory_writable

# Source common library if not already loaded
if [ -z "${COMMON_LIB_LOADED:-}" ]; then
    # Use local variable if SCRIPT_DIR is already set
    if [ -z "${SCRIPT_DIR:-}" ]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
    source "${SCRIPT_DIR}/../lib/common.sh" 2>/dev/null || true
    COMMON_LIB_LOADED=true
fi

# Self-test if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Validation library v${LIB_VALIDATION_VERSION} loaded successfully"
    echo ""
    echo "Running self-tests..."

    # Test email validation
    if validate_email "test@example.com"; then
        echo "✓ Email validation test passed"
    else
        echo "✗ Email validation test failed"
    fi

    # Test domain validation
    if validate_domain "example.com"; then
        echo "✓ Domain validation test passed"
    else
        echo "✗ Domain validation test failed"
    fi

    # Test IP validation
    if validate_ip "192.168.1.1"; then
        echo "✓ IP validation test passed"
    else
        echo "✗ IP validation test failed"
    fi

    echo ""
    echo "Validation library ready for use"
fi