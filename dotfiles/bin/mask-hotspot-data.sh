#!/usr/bin/env bash

set -euo pipefail

# Script configuration
SCRIPT_NAME="$(basename "$0")"
VERSION="1.0.0"
TTL_VALUE=65

# Output control
VERBOSE=0
QUIET=0

# Color codes for output (disabled in quiet mode)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# User Interface Functions
# ============================================================================

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Masks network traffic by setting TTL/Hop Limit values to $TTL_VALUE.
Automatically detects and uses the appropriate firewall backend (iptables or nftables).

OPTIONS:
    -c, --check      Check if TTL masking is already applied
    -r, --remove     Remove TTL masking rules
    -v, --verbose    Enable verbose output (show technical details)
    -q, --quiet      Suppress all output except errors
    -h, --help       Display this help message
    -V, --version    Display version information

EXAMPLES:
    $SCRIPT_NAME              Apply TTL masking
    $SCRIPT_NAME --check      Check current status
    $SCRIPT_NAME --remove     Remove masking rules
    $SCRIPT_NAME --verbose    Apply with detailed output

EOF
}

version_info() {
    echo "$SCRIPT_NAME version $VERSION"
}

log_info() {
    [[ $QUIET -eq 1 ]] && return 0
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_verbose() {
    [[ $VERBOSE -eq 0 ]] && return 0
    echo -e "${YELLOW}[DEBUG]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    [[ $QUIET -eq 1 ]] && return 0
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

# ============================================================================
# Firewall Detection and Management (Internal Implementation)
# ============================================================================

detect_firewall() {
    log_verbose "Detecting firewall backend..."

    # Check if nft command exists (nftables doesn't require active rules to be detected)
    if command -v nft &> /dev/null; then
        log_verbose "Detected: nftables (available)"
        echo "nftables"
        return 0
    fi

    # Fall back to iptables detection
    if command -v iptables &> /dev/null; then
        if iptables -V 2>/dev/null | grep -q "nf_tables"; then
            if command -v iptables-legacy &> /dev/null && \
               iptables-legacy -L -t mangle -n 2>/dev/null | grep -qv "^Chain\|^target"; then
                log_verbose "Detected: iptables-legacy (active)"
                echo "iptables-legacy"
                return 0
            else
                log_verbose "Detected: iptables-nft"
                echo "iptables-nft"
                return 0
            fi
        else
            log_verbose "Detected: iptables-legacy"
            echo "iptables-legacy"
            return 0
        fi
    fi

    log_error "No supported firewall backend detected"
    log_error "Please ensure either iptables or nftables is installed"
    echo "unknown"
    return 1
}

check_rules_iptables() {
    local iptables_cmd="$1"
    log_verbose "Checking for existing rules using $iptables_cmd..."

    if [[ "$iptables_cmd" == "iptables-legacy" ]] && command -v iptables-legacy &> /dev/null; then
        iptables-legacy -L -t mangle -n 2>/dev/null | grep -q "$TTL_VALUE" && return 0
    elif command -v iptables &> /dev/null; then
        iptables -L -t mangle -n 2>/dev/null | grep -q "$TTL_VALUE" && return 0
    fi

    return 1
}

check_rules_nftables() {
    log_verbose "Checking for existing rules using nftables..."
    # Check if the mangle table exists and has our TTL rules
    if sudo nft list table inet mangle 2>/dev/null | grep -q "ip ttl set $TTL_VALUE"; then
        return 0
    fi
    return 1
}

apply_rules_iptables() {
    local iptables_cmd="$1"
    log_verbose "Applying rules using $iptables_cmd..."

    if [[ "$iptables_cmd" == "iptables-legacy" ]] && command -v iptables-legacy &> /dev/null; then
        sudo ip6tables-legacy -t mangle -I POSTROUTING -j HL --hl-set $TTL_VALUE
        sudo ip6tables-legacy -t mangle -I PREROUTING -j HL --hl-set $TTL_VALUE
        sudo iptables-legacy -t mangle -I POSTROUTING -j TTL --ttl-set $TTL_VALUE
        sudo iptables-legacy -t mangle -I PREROUTING -j TTL --ttl-set $TTL_VALUE
        [[ $VERBOSE -eq 1 ]] && sudo iptables-legacy -L -t mangle --line-numbers
    else
        sudo ip6tables -t mangle -I POSTROUTING -j HL --hl-set $TTL_VALUE
        sudo ip6tables -t mangle -I PREROUTING -j HL --hl-set $TTL_VALUE
        sudo iptables -t mangle -I POSTROUTING -j TTL --ttl-set $TTL_VALUE
        sudo iptables -t mangle -I PREROUTING -j TTL --ttl-set $TTL_VALUE
        [[ $VERBOSE -eq 1 ]] && sudo iptables -L -t mangle --line-numbers
    fi
}

apply_rules_nftables() {
    log_verbose "Applying rules using nftables..."

    # Create table and chains (these commands are idempotent - won't error if already exists)
    sudo nft add table inet mangle 2>/dev/null || true
    sudo nft add chain inet mangle prerouting '{ type filter hook prerouting priority -150; policy accept; }' 2>/dev/null || true
    sudo nft add chain inet mangle postrouting '{ type filter hook postrouting priority -150; policy accept; }' 2>/dev/null || true

    # Add rules
    sudo nft add rule inet mangle prerouting ip ttl set $TTL_VALUE
    sudo nft add rule inet mangle prerouting ip6 hoplimit set $TTL_VALUE
    sudo nft add rule inet mangle postrouting ip ttl set $TTL_VALUE
    sudo nft add rule inet mangle postrouting ip6 hoplimit set $TTL_VALUE

    [[ $VERBOSE -eq 1 ]] && sudo nft list table inet mangle
}

remove_rules_iptables() {
    local iptables_cmd="$1"
    log_verbose "Removing rules using $iptables_cmd..."

    if [[ "$iptables_cmd" == "iptables-legacy" ]] && command -v iptables-legacy &> /dev/null; then
        sudo iptables-legacy -t mangle -D POSTROUTING -j TTL --ttl-set $TTL_VALUE 2>/dev/null || true
        sudo iptables-legacy -t mangle -D PREROUTING -j TTL --ttl-set $TTL_VALUE 2>/dev/null || true
        sudo ip6tables-legacy -t mangle -D POSTROUTING -j HL --hl-set $TTL_VALUE 2>/dev/null || true
        sudo ip6tables-legacy -t mangle -D PREROUTING -j HL --hl-set $TTL_VALUE 2>/dev/null || true
    else
        sudo iptables -t mangle -D POSTROUTING -j TTL --ttl-set $TTL_VALUE 2>/dev/null || true
        sudo iptables -t mangle -D PREROUTING -j TTL --ttl-set $TTL_VALUE 2>/dev/null || true
        sudo ip6tables -t mangle -D POSTROUTING -j HL --hl-set $TTL_VALUE 2>/dev/null || true
        sudo ip6tables -t mangle -D PREROUTING -j HL --hl-set $TTL_VALUE 2>/dev/null || true
    fi
}

remove_rules_nftables() {
    log_verbose "Removing rules using nftables..."

    # Flush and delete the mangle table
    sudo nft flush table inet mangle 2>/dev/null || true
    sudo nft delete table inet mangle 2>/dev/null || true
}

# ============================================================================
# Main Operations
# ============================================================================

check_status() {
    local firewall_type
    firewall_type=$(detect_firewall) || exit 1

    case "$firewall_type" in
        "iptables-legacy"|"iptables-nft")
            if check_rules_iptables "$firewall_type"; then
                log_success "TTL masking is active"
                return 0
            else
                log_info "TTL masking is not active"
                return 1
            fi
            ;;
        "nftables")
            if check_rules_nftables; then
                log_success "TTL masking is active"
                return 0
            else
                log_info "TTL masking is not active"
                return 1
            fi
            ;;
        *)
            log_error "Unsupported firewall type"
            exit 1
            ;;
    esac
}

apply_masking() {
    local firewall_type
    firewall_type=$(detect_firewall) || exit 1

    case "$firewall_type" in
        "iptables-legacy"|"iptables-nft")
            if check_rules_iptables "$firewall_type"; then
                log_info "TTL masking already active"
                return 0
            fi
            log_info "Applying TTL masking..."
            apply_rules_iptables "$firewall_type"
            log_success "TTL masking applied successfully"
            ;;
        "nftables")
            if check_rules_nftables; then
                log_info "TTL masking already active"
                return 0
            fi
            log_info "Applying TTL masking..."
            apply_rules_nftables
            log_success "TTL masking applied successfully"
            ;;
        *)
            log_error "Unsupported firewall type"
            exit 1
            ;;
    esac
}

remove_masking() {
    local firewall_type
    firewall_type=$(detect_firewall) || exit 1

    case "$firewall_type" in
        "iptables-legacy"|"iptables-nft")
            log_info "Removing TTL masking..."
            remove_rules_iptables "$firewall_type"
            log_success "TTL masking removed successfully"
            ;;
        "nftables")
            log_info "Removing TTL masking..."
            remove_rules_nftables
            log_success "TTL masking removed successfully"
            ;;
        *)
            log_error "Unsupported firewall type"
            exit 1
            ;;
    esac
}

# ============================================================================
# Command Line Parsing
# ============================================================================

ACTION="apply"

# Parse long options manually
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -V|--version)
            version_info
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -q|--quiet)
            QUIET=1
            shift
            ;;
        -c|--check)
            ACTION="check"
            shift
            ;;
        -r|--remove)
            ACTION="remove"
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            log_error "Unexpected argument: $1"
            usage
            exit 1
            ;;
    esac
done

# ============================================================================
# Main Execution
# ============================================================================

case "$ACTION" in
    check)
        check_status
        ;;
    remove)
        remove_masking
        ;;
    apply)
        apply_masking
        ;;
esac
