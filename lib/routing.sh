#!/bin/bash
# lib/routing.sh - Routing table management and inspection

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Show routing table for a subnet
show_routes() {
    local subnet_name=$1
    
    if [[ -z "$subnet_name" ]]; then
        log_error "Subnet name is required"
        return 1
    fi
    
    if ! netns_exists "$subnet_name"; then
        log_error "Subnet '$subnet_name' does not exist"
        return 1
    fi
    
    log_info "Routing table for subnet '$subnet_name':"
    echo ""
    
    # Show the routing table inside the namespace
    # WHY: Each namespace has its OWN routing table
    ip netns exec "$subnet_name" ip route show
    
    echo ""
    log_info "ARP table (MAC address mappings):"
    ip netns exec "$subnet_name" ip neigh show
}

# Show bridge forwarding table
# WHY: The bridge maintains a MAC address table (like a switch)
# This shows which MAC addresses are reachable via which ports
show_bridge_fdb() {
    local vpc_name=$1
    
    if ! bridge_exists "$vpc_name"; then
        log_error "VPC '$vpc_name' does not exist"
        return 1
    fi
    
    log_info "Bridge forwarding database for '$vpc_name':"
    echo ""
    
    # FDB = Forwarding Database (MAC address table)
    bridge fdb show br "$vpc_name"
}

# Test connectivity between two subnets
test_connectivity() {
    local source_subnet=$1
    local dest_ip=$2
    local count=${3:-3}  # Default 3 pings
    
    if [[ -z "$source_subnet" ]] || [[ -z "$dest_ip" ]]; then
        log_error "Usage: test_connectivity <source_subnet> <dest_ip> [count]"
        return 1
    fi
    
    if ! netns_exists "$source_subnet"; then
        log_error "Source subnet '$source_subnet' does not exist"
        return 1
    fi
    
    log_info "Testing connectivity from '$source_subnet' to $dest_ip..."
    
    # Run ping from inside the source namespace
    if ip netns exec "$source_subnet" ping -c "$count" -W 2 "$dest_ip"; then
        log_success "✓ Connectivity successful"
        return 0
    else
        log_error "✗ Connectivity failed"
        
        # Provide debugging hints
        echo ""
        log_info "Debugging hints:"
        echo "  1. Check if destination subnet exists"
        echo "  2. Verify IP forwarding: sysctl net.ipv4.ip_forward"
        echo "  3. Check routes: vpcctl show-routes $source_subnet"
        echo "  4. Verify both veth interfaces are UP"
        return 1
    fi
}

# Trace packet path between subnets
# This is a debugging tool to understand routing
trace_route() {
    local source_subnet=$1
    local dest_ip=$2
    
    if [[ -z "$source_subnet" ]] || [[ -z "$dest_ip" ]]; then
        log_error "Usage: trace_route <source_subnet> <dest_ip>"
        return 1
    fi
    
    if ! netns_exists "$source_subnet"; then
        log_error "Source subnet '$source_subnet' does not exist"
        return 1
    fi
    
    log_info "Tracing route from '$source_subnet' to $dest_ip..."
    
    # Use traceroute if available, otherwise use ping with TTL
    if command -v traceroute &> /dev/null; then
        ip netns exec "$source_subnet" traceroute -n -m 5 "$dest_ip"
    else
        # Fallback: manual TTL-based tracing
        log_warn "traceroute not installed, using ping with TTL"
        for ttl in {1..5}; do
            echo "TTL=$ttl:"
            ip netns exec "$source_subnet" ping -c 1 -W 1 -t "$ttl" "$dest_ip" 2>&1 | grep "From"
        done
    fi
}

# Show all network interfaces in a subnet
show_interfaces() {
    local subnet_name=$1
    
    if [[ -z "$subnet_name" ]]; then
        log_error "Subnet name is required"
        return 1
    fi
    
    if ! netns_exists "$subnet_name"; then
        log_error "Subnet '$subnet_name' does not exist"
        return 1
    fi
    
    log_info "Network interfaces in subnet '$subnet_name':"
    echo ""
    
    # Show brief interface list
    ip netns exec "$subnet_name" ip -br link show
    
    echo ""
    log_info "IP addresses:"
    ip netns exec "$subnet_name" ip -br addr show
}

# Verify bridge learning (MAC addresses)
# WHY: This proves the bridge is learning which MACs are on which ports
verify_bridge_learning() {
    local vpc_name=$1
    
    if ! bridge_exists "$vpc_name"; then
        log_error "VPC '$vpc_name' does not exist"
        return 1
    fi
    
    log_info "Verifying bridge MAC learning for '$vpc_name'..."
    echo ""
    
    # Show bridge ports (veth interfaces connected)
    log_info "Connected ports:"
    bridge link show | grep "$vpc_name"
    
    echo ""
    log_info "Learned MAC addresses:"
    bridge fdb show br "$vpc_name" | grep -v "permanent" | grep -v "self"
    
    # Count learned MACs (excluding permanent entries)
    local learned_count=$(bridge fdb show br "$vpc_name" | grep -v "permanent" | grep -v "self" | wc -l)
    
    if [[ $learned_count -gt 0 ]]; then
        log_success "Bridge has learned $learned_count MAC address(es)"
    else
        log_warn "No dynamic MAC addresses learned yet (try pinging between subnets)"
    fi
}