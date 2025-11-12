#!/bin/bash
# lib/utils.sh - Utility functions for logging and validation

# Color codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' not found. Please install it."
        exit 1
    fi
}

# Validate IP address format
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    return 0
}

# Validate CIDR notation
validate_cidr() {
    local cidr=$1
    if [[ ! $cidr =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 1
    fi
    return 0
}

# Check if bridge exists
bridge_exists() {
    local bridge=$1
    ip link show "$bridge" &> /dev/null
    return $?
}

# Check if namespace exists
netns_exists() {
    local ns=$1
    
    # Method 1: Check ip netns list output
    if ip netns list 2>/dev/null | grep -qw "^${ns}"; then
        return 0
    fi
    
    # Method 2: Try to execute in namespace
    if ip netns exec "$ns" true 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Enable IP forwarding (required for routing between namespaces)
# WHY: Without this, the kernel drops packets not destined for itself
enable_ip_forward() {
    log_info "Enabling IP forwarding..."
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    
    # Why check this?
    # Some systems have AppArmor/SELinux that might block sysctl changes
    local forward_status=$(sysctl -n net.ipv4.ip_forward)
    if [[ "$forward_status" != "1" ]]; then
        log_error "Failed to enable IP forwarding"
        return 1
    fi
    
    log_success "IP forwarding enabled"
    return 0
}

# Generate a unique identifier (for automated testing)
generate_id() {
    echo "$(date +%s)-$$" # timestamp + process ID
}