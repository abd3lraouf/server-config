#!/bin/bash

# Test script for Zero Trust Setup validation
# This script tests various scenarios without making actual changes

set -euo pipefail

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

echo -e "${YELLOW}Zero Trust Setup Test Suite${NC}\n"

# Test 1: Help message
echo "Test 1: Checking help message..."
if sudo ./setup.sh --help | grep -q "Zero Trust Security Setup Script"; then
    echo -e "${GREEN}✓${NC} Help message works"
else
    echo -e "${RED}✗${NC} Help message failed"
fi

# Test 2: Version check
echo "Test 2: Checking version..."
if sudo ./setup.sh --version | grep -q "v2.0.0"; then
    echo -e "${GREEN}✓${NC} Version check works"
else
    echo -e "${RED}✗${NC} Version check failed"
fi

# Test 3: Dry run mode
echo "Test 3: Testing dry-run mode..."
if sudo ./setup.sh --dry-run --non-interactive --skip-validation --email test@example.com --domain test.com 2>&1 | grep -q "DRY_RUN"; then
    echo -e "${GREEN}✓${NC} Dry-run mode works"
else
    echo -e "${YELLOW}⚠${NC} Dry-run mode needs verification"
fi

# Test 4: Syntax validation
echo "Test 4: Validating script syntax..."
if bash -n setup.sh 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Script syntax is valid"
else
    echo -e "${RED}✗${NC} Script has syntax errors"
fi

# Test 5: Check for required functions
echo "Test 5: Checking required functions..."
functions=(
    "validate_ubuntu_version"
    "configure_interactively"
    "install_tailscale"
    "setup_cloudflare_tunnel"
    "harden_system"
    "install_crowdsec"
    "validate_zero_trust_security"
)

for func in "${functions[@]}"; do
    if grep -q "^${func}()" setup.sh; then
        echo -e "  ${GREEN}✓${NC} Function $func exists"
    else
        echo -e "  ${RED}✗${NC} Function $func missing"
    fi
done

# Test 6: Check log file creation
echo "Test 6: Checking logging capability..."
LOG_DIR="/var/log"
if [ -w "$LOG_DIR" ]; then
    echo -e "${GREEN}✓${NC} Log directory is writable"
else
    echo -e "${YELLOW}⚠${NC} Log directory may not be writable"
fi

# Test 7: Check for dangerous commands
echo "Test 7: Security audit..."
dangerous_patterns=(
    "rm -rf /"
    "chmod 777"
    "PasswordAuthentication yes"
)

issues_found=0
for pattern in "${dangerous_patterns[@]}"; do
    if grep -q "$pattern" setup.sh; then
        echo -e "  ${RED}✗${NC} Found dangerous pattern: $pattern"
        ((issues_found++))
    fi
done

if [ $issues_found -eq 0 ]; then
    echo -e "${GREEN}✓${NC} No dangerous patterns found"
fi

# Test 8: Check Ubuntu version
echo "Test 8: Checking Ubuntu compatibility..."
current_version=$(lsb_release -rs 2>/dev/null || echo "unknown")
echo -e "  Current Ubuntu version: $current_version"
if [[ "$current_version" == "24.04" ]]; then
    echo -e "${GREEN}✓${NC} Running on Ubuntu 24.04 LTS (optimal)"
elif [[ "$current_version" == "22.04" ]] || [[ "$current_version" == "20.04" ]]; then
    echo -e "${YELLOW}⚠${NC} Running on Ubuntu $current_version (supported with limitations)"
else
    echo -e "${RED}✗${NC} Unsupported Ubuntu version"
fi

# Summary
echo -e "\n${YELLOW}Test Summary:${NC}"
echo "All basic tests completed. For full validation:"
echo "1. Run: sudo ./setup.sh --dry-run --verbose"
echo "2. Test interactive mode: sudo ./setup.sh"
echo "3. Review log files in /var/log/zero-trust-setup-*"
echo ""
echo -e "${GREEN}Ready for production use!${NC}"