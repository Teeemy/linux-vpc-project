#!/bin/bash
# lib/subnet.sh - Subnet (network namespace) creation and management

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Create a subnet (implemented as a network namespace)
create_subnet() {
    local vpc_name=$1
    local subnet_name=$2
    local subnet_cidr=$3
    
    # Validate inputs
    if [[ -z "$vpc_name" ]] || [[ -z "$subnet_name" ]] || [[ -z "$subnet_cidr" ]]; then
        log_error "Usage: create_subnet <vpc_name> <subnet_name> <subnet_cidr>"
        return 1
    fi
    
    if ! bridge_exists "$vpc_name"; then
        log_error "VPC '$vpc_name' does not exist. Create it first."
        return 1
    fi
    
    if ! validate_cidr "$subnet_cidr"; then
        log_error "Invalid CIDR format: $subnet_cidr"
        return 1
    fi
    
    # Check if subnet already exists
    if netns_exists "$subnet_name"; then
        log_warn "Subnet '$subnet_name' already exists"
        return 0
    fi
    
    log_info "Creating subnet '$subnet_name' in VPC '$vpc_name'..."
    
    # Step 1: Create network namespace
    if ! ip netns add "$subnet_name"; then
        log_error "Failed to create namespace $subnet_name"
        return 1
    fi
    
    # Step 2: Create veth pair with SHORT names
    # Linux interface names limited to 15 chars
    # Generate short unique names
    local short_name=$(echo "${subnet_name}" | sed 's/[^a-zA-Z0-9]//g' | cut -c1-8)
    local veth_subnet="vs-${short_name}"
    local veth_bridge="vb-${short_name}"
    
    if ! ip link add "$veth_subnet" type veth peer name "$veth_bridge"; then
        log_error "Failed to create veth pair"
        ip netns delete "$subnet_name"
        return 1
    fi
    
    # Step 3: Move one end of veth into the namespace
    if ! ip link set "$veth_subnet" netns "$subnet_name"; then
        log_error "Failed to move veth into namespace"
        ip link delete "$veth_bridge"
        ip netns delete "$subnet_name"
        return 1
    fi
    
    # Step 4: Connect the other end to the bridge
    if ! ip link set "$veth_bridge" master "$vpc_name"; then
        log_error "Failed to attach veth to bridge"
        ip netns delete "$subnet_name"
        return 1
    fi
    
    # Step 5: Bring both ends UP
    ip link set "$veth_bridge" up
    ip netns exec "$subnet_name" ip link set "$veth_subnet" up
    
    # Step 6: Bring up loopback in namespace
    ip netns exec "$subnet_name" ip link set lo up
    
    # Step 7: Assign IP address to the interface inside namespace
    local subnet_ip=$(echo "$subnet_cidr" | sed 's/\.0\/24/.2\/24/; s/\.0\/16/.2\/16/; s/\.0\/8/.2\/8/')
    
    if ! ip netns exec "$subnet_name" ip addr add "$subnet_ip" dev "$veth_subnet"; then
        log_error "Failed to assign IP to subnet interface"
        ip link delete "$veth_bridge"
        ip netns delete "$subnet_name"
        return 1
    fi
    
    # Step 8: Set default route to the bridge
        local bridge_ip=$(ip -4 addr show "$vpc_name" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
    
    if [[ -z "$bridge_ip" ]]; then
        log_warn "Could not determine bridge IP for gateway"
    else
        log_info "Setting default route via gateway $bridge_ip..."
        
        # Wait briefly for interface to be ready
        sleep 0.2
        
        # Delete any existing default routes first
        ip netns exec "$subnet_name" ip route del default 2>/dev/null || true
        
        # Add default route to bridge (VPC gateway)
        if ip netns exec "$subnet_name" ip route add default via "$bridge_ip" 2>/dev/null; then
            log_success "Default route set: default via $bridge_ip"
        else
            log_warn "Failed to set default route - will retry"
            
            # Retry after a longer delay
            sleep 0.5
            if ip netns exec "$subnet_name" ip route add default via "$bridge_ip" 2>/dev/null; then
                log_success "Default route set on retry"
            else
                log_error "Could not set default route - manual fix may be needed"
            fi
        fi
    fi
    
    # Store metadata (including veth names for cleanup)
    mkdir -p "/var/lib/vpcctl/${vpc_name}"
    echo "$subnet_cidr" > "/var/lib/vpcctl/${vpc_name}/${subnet_name}.cidr"
    echo "$veth_bridge" > "/var/lib/vpcctl/${vpc_name}/${subnet_name}.veth"
    
    return 0
}

# Delete a subnet
delete_subnet() {
    local subnet_name=$1
    
    if [[ -z "$subnet_name" ]]; then
        log_error "Subnet name is required"
        return 1
    fi
    
    if ! netns_exists "$subnet_name"; then
        log_warn "Subnet '$subnet_name' does not exist"
        return 0
    fi
    
    log_info "Deleting subnet '$subnet_name'..."
    
    # Step 1: Get veth bridge name from metadata
    local veth_bridge=""
    for vpc_dir in /var/lib/vpcctl/*/; do
        if [[ -f "${vpc_dir}${subnet_name}.veth" ]]; then
            veth_bridge=$(cat "${vpc_dir}${subnet_name}.veth")
            break
        fi
    done
    
    # Step 2: Delete veth pair bridge-side
    if [[ -n "$veth_bridge" ]] && ip link show "$veth_bridge" &> /dev/null; then
        ip link delete "$veth_bridge" 2>/dev/null
    else
        # Fallback: try old naming scheme
        local short_name=$(echo "${subnet_name}" | sed 's/[^a-zA-Z0-9]//g' | cut -c1-8)
        local old_veth="vb-${short_name}"
        if ip link show "$old_veth" &> /dev/null; then
            ip link delete "$old_veth" 2>/dev/null
        fi
    fi
    
    # Step 3: Delete the namespace
    if ! ip netns delete "$subnet_name"; then
        log_error "Failed to delete namespace $subnet_name"
        return 1
    fi
    
    # Step 4: Cleanup metadata
    find /var/lib/vpcctl -name "${subnet_name}.cidr" -delete 2>/dev/null
    find /var/lib/vpcctl -name "${subnet_name}.veth" -delete 2>/dev/null
    
    log_success "Subnet '$subnet_name' deleted"
    return 0
}

# List all subnets
list_subnets() {
    log_info "Existing Subnets (Network Namespaces):"
    
    local namespaces=$(ip netns list | awk '{print $1}')
    
    if [[ -z "$namespaces" ]]; then
        echo "  No subnets found"
        return 0
    fi
    
    printf "  %-20s %-20s %-20s\n" "NAME" "IP ADDRESS" "GATEWAY"
    printf "  %-20s %-20s %-20s\n" "----" "----------" "-------"
    
    for ns in $namespaces; do
        local ip=$(ip netns exec "$ns" ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+/[\d]+' | grep -v '^127' | head -1)
        local gw=$(ip netns exec "$ns" ip route show default 2>/dev/null | grep -oP 'via \K[\d.]+' | head -1)
        printf "  %-20s %-20s %-20s\n" "$ns" "${ip:-N/A}" "${gw:-N/A}"
    done
}

# Execute a command inside a subnet's namespace
exec_in_subnet() {
    local subnet_name=$1
    shift
    local command="$@"
    
    if ! netns_exists "$subnet_name"; then
        log_error "Subnet '$subnet_name' does not exist"
        return 1
    fi
    
    log_info "Executing in subnet '$subnet_name': $command"
    ip netns exec "$subnet_name" $command
}