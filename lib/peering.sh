#!/bin/bash
# lib/peering.sh - VPC peering management

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Create a peering connection between two VPCs
peer_vpcs() {
    local vpc_a=$1
    local vpc_b=$2
    
    if [[ -z "$vpc_a" ]] || [[ -z "$vpc_b" ]]; then
        log_error "Usage: peer_vpcs <vpc_a> <vpc_b>"
        return 1
    fi
    
    # Validate both VPCs exist
    if ! bridge_exists "$vpc_a"; then
        log_error "VPC '$vpc_a' does not exist"
        return 1
    fi
    
    if ! bridge_exists "$vpc_b"; then
        log_error "VPC '$vpc_b' does not exist"
        return 1
    fi
    
    # Check if peering already exists
    local peer_name_a="peer-${vpc_a}-${vpc_b}"
    local peer_name_b="peer-${vpc_b}-${vpc_a}"
    
    if ip link show "$peer_name_a" &> /dev/null; then
        log_warn "Peering already exists between '$vpc_a' and '$vpc_b'"
        return 0
    fi
    
    log_info "Creating peering between '$vpc_a' and '$vpc_b'..."
    
    # Get CIDR ranges for routing
    local cidr_a=$(cat "/var/lib/vpcctl/${vpc_a}.cidr" 2>/dev/null)
    local cidr_b=$(cat "/var/lib/vpcctl/${vpc_b}.cidr" 2>/dev/null)
    
    if [[ -z "$cidr_a" ]] || [[ -z "$cidr_b" ]]; then
        log_error "Could not determine VPC CIDR ranges"
        return 1
    fi
    
    # Create veth pair for peering
    if ! ip link add "$peer_name_a" type veth peer name "$peer_name_b"; then
        log_error "Failed to create peering veth pair"
        return 1
    fi
    
    # Attach veth ends to respective bridges
    if ! ip link set "$peer_name_a" master "$vpc_a"; then
        log_error "Failed to attach peering to VPC '$vpc_a'"
        ip link delete "$peer_name_a"
        return 1
    fi
    
    if ! ip link set "$peer_name_b" master "$vpc_b"; then
        log_error "Failed to attach peering to VPC '$vpc_b'"
        ip link delete "$peer_name_a"
        return 1
    fi
    
    # Bring both ends UP
    ip link set "$peer_name_a" up
    ip link set "$peer_name_b" up
    
    # Add routes so each VPC knows about the other's CIDR
    # Route from VPC-A to VPC-B's network
    if ! ip route add "$cidr_b" dev "$peer_name_a" 2>/dev/null; then
        log_warn "Route from $vpc_a to $cidr_b may already exist"
    fi
    
    # Route from VPC-B to VPC-A's network
    if ! ip route add "$cidr_a" dev "$peer_name_b" 2>/dev/null; then
        log_warn "Route from $vpc_b to $cidr_a may already exist"
    fi
    
    log_success "✓ Peering established between '$vpc_a' and '$vpc_b'"
    
    # Store peering metadata
    mkdir -p /var/lib/vpcctl/peerings
    echo "$vpc_b" > "/var/lib/vpcctl/peerings/${vpc_a}-${vpc_b}"
    echo "$vpc_a" > "/var/lib/vpcctl/peerings/${vpc_b}-${vpc_a}"
    
    return 0
}

# Remove peering between two VPCs
unpeer_vpcs() {
    local vpc_a=$1
    local vpc_b=$2
    
    if [[ -z "$vpc_a" ]] || [[ -z "$vpc_b" ]]; then
        log_error "Usage: unpeer_vpcs <vpc_a> <vpc_b>"
        return 1
    fi
    
    local peer_name_a="peer-${vpc_a}-${vpc_b}"
    local peer_name_b="peer-${vpc_b}-${vpc_a}"
    
    if ! ip link show "$peer_name_a" &> /dev/null; then
        log_warn "No peering exists between '$vpc_a' and '$vpc_b'"
        return 0
    fi
    
    log_info "Removing peering between '$vpc_a' and '$vpc_b'..."
    
    # Get CIDR ranges
    local cidr_a=$(cat "/var/lib/vpcctl/${vpc_a}.cidr" 2>/dev/null)
    local cidr_b=$(cat "/var/lib/vpcctl/${vpc_b}.cidr" 2>/dev/null)
    
    # Remove routes
    if [[ -n "$cidr_b" ]]; then
        ip route del "$cidr_b" dev "$peer_name_a" 2>/dev/null || true
    fi
    
    if [[ -n "$cidr_a" ]]; then
        ip route del "$cidr_a" dev "$peer_name_b" 2>/dev/null || true
    fi
    
    # Delete veth pair (deleting one end deletes both)
    ip link delete "$peer_name_a" 2>/dev/null || true
    
    # Remove metadata
    rm -f "/var/lib/vpcctl/peerings/${vpc_a}-${vpc_b}"
    rm -f "/var/lib/vpcctl/peerings/${vpc_b}-${vpc_a}"
    
    log_success "Peering removed between '$vpc_a' and '$vpc_b'"
    return 0
}

# List all VPC peerings
list_peerings() {
    log_info "VPC Peering Connections:"
    echo ""
    
    if [[ ! -d /var/lib/vpcctl/peerings ]] || [[ -z "$(ls -A /var/lib/vpcctl/peerings 2>/dev/null)" ]]; then
        echo "  No VPC peerings configured"
        return 0
    fi
    
    printf "  %-20s %-20s %-10s\n" "VPC-A" "VPC-B" "STATUS"
    printf "  %-20s %-20s %-10s\n" "-----" "-----" "------"
    
    # Track which peerings we've already printed (avoid duplicates)
    local printed=()
    
    for peering_file in /var/lib/vpcctl/peerings/*; do
        local filename=$(basename "$peering_file")
        
        # Skip if we've already printed this peering
        if [[ " ${printed[@]} " =~ " ${filename} " ]]; then
            continue
        fi
        
        # Parse VPC names from filename (format: vpca-vpcb)
        local vpc_a=$(echo "$filename" | cut -d'-' -f1)
        local vpc_b=$(echo "$filename" | cut -d'-' -f2)
        
        # Check if peering interface exists
        local peer_name="peer-${vpc_a}-${vpc_b}"
        local status="INACTIVE"
        
        if ip link show "$peer_name" &> /dev/null; then
            local link_state=$(ip link show "$peer_name" | grep -oP 'state \K\w+')
            if [[ "$link_state" == "UP" ]]; then
                status="ACTIVE"
            fi
        fi
        
        printf "  %-20s %-20s %-10s\n" "$vpc_a" "$vpc_b" "$status"
        
        # Mark both directions as printed
        printed+=("$filename")
        printed+=("${vpc_b}-${vpc_a}")
    done
}

# Show details of a specific peering
show_peering() {
    local vpc_a=$1
    local vpc_b=$2
    
    if [[ -z "$vpc_a" ]] || [[ -z "$vpc_b" ]]; then
        log_error "Usage: show_peering <vpc_a> <vpc_b>"
        return 1
    fi
    
    local peer_name_a="peer-${vpc_a}-${vpc_b}"
    
    if ! ip link show "$peer_name_a" &> /dev/null; then
        log_error "No peering exists between '$vpc_a' and '$vpc_b'"
        return 1
    fi
    
    log_info "Peering Details: $vpc_a ↔ $vpc_b"
    echo ""
    
    # Show interface details
    echo "Peering Interfaces:"
    ip -d link show "$peer_name_a"
    echo ""
    
    # Show routes
    echo "Routes via peering:"
    ip route show | grep "$peer_name_a" || echo "  No routes found"
    
    return 0
}

# Test connectivity between peered VPCs
test_peering() {
    local vpc_a=$1
    local vpc_b=$2
    
    if [[ -z "$vpc_a" ]] || [[ -z "$vpc_b" ]]; then
        log_error "Usage: test_peering <vpc_a> <vpc_b>"
        return 1
    fi
    
    log_info "Testing peering between '$vpc_a' and '$vpc_b'..."
    echo ""
    
    # Find a subnet in each VPC
    local subnet_a=""
    local subnet_b=""
    local ip_a=""
    local ip_b=""
    
    # Find subnet in VPC-A
    for ns in $(ip netns list | awk '{print $1}'); do
        if [[ -f "/var/lib/vpcctl/${vpc_a}/${ns}.cidr" ]]; then
            subnet_a="$ns"
            ip_a=$(ip netns exec "$ns" ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '^127' | head -1)
            break
        fi
    done
    
    # Find subnet in VPC-B
    for ns in $(ip netns list | awk '{print $1}'); do
        if [[ -f "/var/lib/vpcctl/${vpc_b}/${ns}.cidr" ]]; then
            subnet_b="$ns"
            ip_b=$(ip netns exec "$ns" ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '^127' | head -1)
            break
        fi
    done
    
    if [[ -z "$subnet_a" ]] || [[ -z "$subnet_b" ]]; then
        log_error "Could not find subnets in both VPCs"
        return 1
    fi
    
    log_info "Testing: $subnet_a ($ip_a) → $subnet_b ($ip_b)"
    
    if ip netns exec "$subnet_a" ping -c 3 -W 2 "$ip_b" > /dev/null 2>&1; then
        log_success "✓ Peering is working! VPC-A can reach VPC-B"
        return 0
    else
        log_error "✗ Peering test failed"
        return 1
    fi
}
