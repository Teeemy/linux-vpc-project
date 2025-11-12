#!/bin/bash
# lib/nat.sh - NAT gateway management

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Enable NAT for a subnet
enable_nat() {
    local subnet_name=$1
    local subnet_cidr=$2
    
    if [[ -z "$subnet_name" ]] || [[ -z "$subnet_cidr" ]]; then
        log_error "Usage: enable_nat <subnet_name> <subnet_cidr>"
        return 1
    fi
    
    if ! netns_exists "$subnet_name"; then
        log_error "Subnet '$subnet_name' does not exist"
        return 1
    fi
    
    if ! validate_cidr "$subnet_cidr"; then
        log_error "Invalid CIDR: $subnet_cidr"
        return 1
    fi
    
    log_info "Enabling NAT for subnet '$subnet_name' ($subnet_cidr)..."
    
    # Get the default outgoing interface
    local wan_interface=$(ip route show default | awk '/default/ {print $5}' | head -1)
    
    if [[ -z "$wan_interface" ]]; then
        log_error "Cannot determine default network interface"
        log_info "Run: ip route show default"
        return 1
    fi
    
    log_info "Using outgoing interface: $wan_interface"
    
    # Enable IP forwarding
    enable_ip_forward
    
    # Check if NAT rule already exists
    if iptables -t nat -C POSTROUTING -s "$subnet_cidr" -o "$wan_interface" -j MASQUERADE 2>/dev/null; then
        log_warn "NAT rule already exists for $subnet_cidr"
        return 0
    fi
    
    # Add MASQUERADE rule
    if ! iptables -t nat -A POSTROUTING -s "$subnet_cidr" -o "$wan_interface" -j MASQUERADE; then
        log_error "Failed to add MASQUERADE rule"
        return 1
    fi
    
    # Allow forwarding from subnet to WAN
    if ! iptables -A FORWARD -s "$subnet_cidr" -o "$wan_interface" -j ACCEPT; then
        log_warn "Failed to add FORWARD ACCEPT rule (may already exist)"
    fi
    
    # Allow established connections back
    if ! iptables -A FORWARD -i "$wan_interface" -m state --state RELATED,ESTABLISHED -j ACCEPT; then
        log_warn "Failed to add FORWARD ESTABLISHED rule (may already exist)"
    fi
    
    log_success "✓ NAT enabled for subnet '$subnet_name'"
    log_info "Subnet can now reach internet via $wan_interface"
    
    # Store NAT metadata
    mkdir -p /var/lib/vpcctl/nat
    echo "$wan_interface" > "/var/lib/vpcctl/nat/${subnet_name}.interface"
    echo "$subnet_cidr" > "/var/lib/vpcctl/nat/${subnet_name}.cidr"
    
    return 0
}

# Disable NAT for a subnet
disable_nat() {
    local subnet_name=$1
    
    if [[ -z "$subnet_name" ]]; then
        log_error "Subnet name is required"
        return 1
    fi
    
    if [[ ! -f "/var/lib/vpcctl/nat/${subnet_name}.cidr" ]]; then
        log_warn "No NAT configuration found for '$subnet_name'"
        return 0
    fi
    
    log_info "Disabling NAT for subnet '$subnet_name'..."
    
    local subnet_cidr=$(cat "/var/lib/vpcctl/nat/${subnet_name}.cidr")
    local wan_interface=$(cat "/var/lib/vpcctl/nat/${subnet_name}.interface")
    
    # Remove MASQUERADE rule
    if iptables -t nat -C POSTROUTING -s "$subnet_cidr" -o "$wan_interface" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -D POSTROUTING -s "$subnet_cidr" -o "$wan_interface" -j MASQUERADE
        log_success "✓ Removed MASQUERADE rule"
    fi
    
    # Remove FORWARD rules
    iptables -D FORWARD -s "$subnet_cidr" -o "$wan_interface" -j ACCEPT 2>/dev/null || true
    
    # Cleanup metadata
    rm -f "/var/lib/vpcctl/nat/${subnet_name}.cidr"
    rm -f "/var/lib/vpcctl/nat/${subnet_name}.interface"
    
    log_success "NAT disabled for '$subnet_name'"
    return 0
}

# List all NAT rules
list_nat_rules() {
    log_info "Active NAT Rules:"
    echo ""
    
    iptables -t nat -L POSTROUTING -n -v --line-numbers | grep -E "MASQUERADE|Chain"
    
    echo ""
    log_info "Subnets with NAT enabled:"
    
    if [[ -d /var/lib/vpcctl/nat ]]; then
        for cidr_file in /var/lib/vpcctl/nat/*.cidr; do
            if [[ -f "$cidr_file" ]]; then
                local subnet=$(basename "$cidr_file" .cidr)
                local cidr=$(cat "$cidr_file")
                local iface=$(cat "/var/lib/vpcctl/nat/${subnet}.interface" 2>/dev/null || echo "unknown")
                printf "  %-20s %-20s → %s\n" "$subnet" "$cidr" "$iface"
            fi
        done
    else
        echo "  No subnets with NAT"
    fi
}

# Test internet connectivity from a subnet
test_internet() {
    local subnet_name=$1
    local test_host=${2:-8.8.8.8}
    
    if [[ -z "$subnet_name" ]]; then
        log_error "Usage: test_internet <subnet_name> [host]"
        return 1
    fi
    
    if ! netns_exists "$subnet_name"; then
        log_error "Subnet '$subnet_name' does not exist"
        return 1
    fi
    
    log_info "Testing internet connectivity from '$subnet_name'..."
    echo ""
    
    log_info "Test 1: Ping $test_host"
    if ip netns exec "$subnet_name" ping -c 3 -W 2 "$test_host" > /dev/null 2>&1; then
        log_success "✓ Can reach $test_host"
    else
        log_error "✗ Cannot reach $test_host"
        log_info "This subnet may not have NAT enabled"
        return 1
    fi
    
    if command -v dig &> /dev/null; then
        echo ""
        log_info "Test 2: DNS resolution (google.com)"
        if ip netns exec "$subnet_name" dig +short google.com @8.8.8.8 | grep -q "^[0-9]"; then
            log_success "✓ DNS resolution works"
        else
            log_warn "✗ DNS resolution failed"
        fi
    fi
    
    if command -v curl &> /dev/null; then
        echo ""
        log_info "Test 3: HTTP connectivity"
        if ip netns exec "$subnet_name" curl -s --connect-timeout 3 -o /dev/null http://google.com; then
            log_success "✓ HTTP connectivity works"
        else
            log_warn "✗ HTTP request failed"
        fi
    fi
    
    echo ""
    log_success "Internet connectivity test complete"
    return 0
}

# Show connection tracking table
show_conntrack() {
    log_info "Active connection tracking entries:"
    echo ""
    
    if command -v conntrack &> /dev/null; then
        conntrack -L -n 2>/dev/null | grep -E "ASSURED|src=" | head -20
    else
        log_warn "conntrack-tools not installed"
        log_info "Install with: sudo apt-get install conntrack"
        echo ""
        log_info "Alternative: viewing /proc/net/nf_conntrack"
        if [[ -f /proc/net/nf_conntrack ]]; then
            head -20 /proc/net/nf_conntrack
        fi
    fi
}

# Verify NAT configuration for a subnet
verify_nat() {
    local subnet_name=$1
    
    if [[ -z "$subnet_name" ]]; then
        log_error "Subnet name is required"
        return 1
    fi
    
    log_info "Verifying NAT configuration for '$subnet_name'..."
    echo ""
    
    if [[ ! -f "/var/lib/vpcctl/nat/${subnet_name}.cidr" ]]; then
        log_error "✗ No NAT configuration found"
        log_info "Enable with: vpcctl enable-nat $subnet_name"
        return 1
    fi
    
    local subnet_cidr=$(cat "/var/lib/vpcctl/nat/${subnet_name}.cidr")
    local wan_interface=$(cat "/var/lib/vpcctl/nat/${subnet_name}.interface")
    
    log_info "Configured NAT:"
    echo "  Subnet CIDR:   $subnet_cidr"
    echo "  WAN Interface: $wan_interface"
    echo ""
    
    log_info "Checking iptables rules..."
    if iptables -t nat -C POSTROUTING -s "$subnet_cidr" -o "$wan_interface" -j MASQUERADE 2>/dev/null; then
        log_success "✓ MASQUERADE rule exists"
    else
        log_error "✗ MASQUERADE rule missing!"
        return 1
    fi
    
    echo ""
    log_info "Checking IP forwarding..."
    if [[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]]; then
        log_success "✓ IP forwarding enabled"
    else
        log_error "✗ IP forwarding disabled"
        return 1
    fi
    
    echo ""
    log_info "Checking WAN interface..."
    if ip link show "$wan_interface" &> /dev/null; then
        local state=$(ip link show "$wan_interface" | grep -oP 'state \K\w+')
        if [[ "$state" == "UP" ]]; then
            log_success "✓ WAN interface is UP"
        else
            log_warn "WAN interface state: $state"
        fi
    else
        log_error "✗ WAN interface not found"
        return 1
    fi
    
    echo ""
    log_success "NAT configuration verified for '$subnet_name'"
    return 0
}