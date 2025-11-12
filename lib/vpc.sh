#!/bin/bash
# lib/vpc.sh - VPC (bridge) creation and management

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Create a VPC (implemented as a Linux bridge)
# WHY BRIDGE: Acts as a Layer 2 switch + Layer 3 router when ip_forward=1
create_vpc() {
    local vpc_name=$1
    local vpc_cidr=$2
    
    # Validate inputs
    if [[ -z "$vpc_name" ]]; then
        log_error "VPC name is required"
        return 1
    fi
    
    if ! validate_cidr "$vpc_cidr"; then
        log_error "Invalid CIDR format: $vpc_cidr"
        return 1
    fi
    
    # Check if VPC already exists (idempotency)
    if bridge_exists "$vpc_name"; then
        log_warn "VPC '$vpc_name' already exists"
        return 0
    fi
    
    log_info "Creating VPC '$vpc_name' with CIDR $vpc_cidr..."
    
    # Step 1: Create the bridge device
    # This is our VPC "router" - all subnets will connect here
    if ! ip link add "$vpc_name" type bridge; then
        log_error "Failed to create bridge $vpc_name"
        return 1
    fi
    
    # Step 2: Bring the bridge UP
    # WHY: Interfaces must be UP to forward packets
    if ! ip link set "$vpc_name" up; then
        log_error "Failed to bring up bridge $vpc_name"
        ip link delete "$vpc_name" # Cleanup on failure
        return 1
    fi
    
    # Step 3: Assign an IP to the bridge itself
    # Calculate gateway IP from CIDR
    # WHY: The bridge needs an IP to act as the default gateway for subnets
    # We use the first IP in the CIDR range (e.g., 10.0.0.1 for 10.0.0.0/16)
    
    local network prefix base bridge_ip
    network=$(echo "$vpc_cidr" | cut -d'/' -f1)
    prefix=$(echo "$vpc_cidr" | cut -d'/' -f2)
    base=$(echo "$network" | cut -d'.' -f1-3)
    bridge_ip="${base}.1/${prefix}"
    
    if ! ip addr add "$bridge_ip" dev "$vpc_name"; then
        log_error "Failed to assign IP $bridge_ip to bridge"
        ip link delete "$vpc_name"
        return 1
    fi
    
    log_success "VPC '$vpc_name' created with IP $bridge_ip"
    
    # Store VPC metadata for later use
    mkdir -p /var/lib/vpcctl
    echo "$vpc_cidr" > "/var/lib/vpcctl/${vpc_name}.cidr"
    
    return 0
}

# Delete a VPC and all associated resources
delete_vpc() {
    local vpc_name=$1
    
    if [[ -z "$vpc_name" ]]; then
        log_error "VPC name is required"
        return 1
    fi
    
    if ! bridge_exists "$vpc_name"; then
        log_warn "VPC '$vpc_name' does not exist"
        return 0
    fi
    
    log_info "Deleting VPC '$vpc_name'..."
    
    # Step 1: Delete all veth pairs connected to this bridge
    # WHY: Must cleanup in reverse order - veth pairs before bridge
    for iface in $(ip link show master "$vpc_name" 2>/dev/null | grep -oP '^\d+: \K[^:@]+'); do
        log_info "Removing interface $iface from bridge"
        ip link set "$iface" nomaster 2>/dev/null
        ip link delete "$iface" 2>/dev/null
    done
    
    # Step 2: Bring bridge down and delete it
    ip link set "$vpc_name" down 2>/dev/null
    if ! ip link delete "$vpc_name"; then
        log_error "Failed to delete bridge $vpc_name"
        return 1
    fi
    
    # Step 3: Cleanup metadata
    rm -f "/var/lib/vpcctl/${vpc_name}.cidr"
    
    log_success "VPC '$vpc_name' deleted"
    return 0
}

# List all VPCs
list_vpcs() {
    log_info "Existing VPCs:"
    
    # Find all bridge interfaces (our VPCs)
    local vpcs=$(ip -br link show type bridge | awk '{print $1}')
    
    if [[ -z "$vpcs" ]]; then
        echo "  No VPCs found"
        return 0
    fi
    
    # Pretty print VPC info
    printf "  %-20s %-20s %-10s\n" "NAME" "IP ADDRESS" "STATE"
    printf "  %-20s %-20s %-10s\n" "----" "----------" "-----"
    
    for vpc in $vpcs; do
        local ip=$(ip -4 addr show "$vpc" | grep -oP 'inet \K[\d.]+/[\d]+' | head -1)
        local state=$(ip -br link show "$vpc" | awk '{print $2}')
        printf "  %-20s %-20s %-10s\n" "$vpc" "${ip:-N/A}" "$state"
    done
}

# Show detailed VPC information
show_vpc() {
    local vpc_name=$1
    
    if ! bridge_exists "$vpc_name"; then
        log_error "VPC '$vpc_name' does not exist"
        return 1
    fi
    
    log_info "VPC Details: $vpc_name"
    echo ""
    
    # Bridge info
    echo "Bridge Information:"
    ip -d link show "$vpc_name"
    echo ""
    
    # IP addresses
    echo "IP Addresses:"
    ip addr show "$vpc_name"
    echo ""
    
    # Connected interfaces
    echo "Connected Interfaces:"
    ip link show master "$vpc_name" 2>/dev/null || echo "  None"
}