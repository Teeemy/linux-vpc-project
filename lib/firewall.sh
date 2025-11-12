#!/bin/bash
# lib/firewall.sh - Security group (firewall) management

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Apply security group to a subnet
apply_security_group() {
    local subnet_name=$1
    local policy_file=$2
    
    if [[ -z "$subnet_name" ]] || [[ -z "$policy_file" ]]; then
        log_error "Usage: apply_security_group <subnet_name> <policy_file>"
        return 1
    fi
    
    if ! netns_exists "$subnet_name"; then
        log_error "Subnet '$subnet_name' does not exist"
        return 1
    fi
    
    if [[ ! -f "$policy_file" ]]; then
        log_error "Policy file not found: $policy_file"
        return 1
    fi
    
    log_info "Applying security group from '$policy_file' to '$subnet_name'..."
    
    # Parse JSON (requires jq)
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for parsing JSON policies"
        log_info "Install with: sudo apt-get install jq"
        return 1
    fi
    
    # Get policy details
    local sg_name=$(jq -r '.name' "$policy_file")
    local default_inbound=$(jq -r '.default_inbound' "$policy_file")
    local default_outbound=$(jq -r '.default_outbound' "$policy_file")
    
    log_info "Security Group: $sg_name"
    
    # Get the veth interface name in the namespace
    local veth_iface=$(ip netns exec "$subnet_name" ip link show | grep -oP '^\d+: \K(vs-[^:@]+)')
    
    if [[ -z "$veth_iface" ]]; then
        log_error "Could not find veth interface in subnet"
        return 1
    fi
    
    log_info "Interface: $veth_iface"
    
    # Flush existing rules for this subnet
    ip netns exec "$subnet_name" iptables -F INPUT 2>/dev/null || true
    ip netns exec "$subnet_name" iptables -F OUTPUT 2>/dev/null || true
    ip netns exec "$subnet_name" iptables -F FORWARD 2>/dev/null || true
    
    # Set default policies
    ip netns exec "$subnet_name" iptables -P INPUT "$default_inbound"
    ip netns exec "$subnet_name" iptables -P OUTPUT "$default_outbound"
    ip netns exec "$subnet_name" iptables -P FORWARD DROP
    
    log_info "Default policies: INPUT=$default_inbound, OUTPUT=$default_outbound"
    
    # Allow established/related connections (stateful firewall)
    ip netns exec "$subnet_name" iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip netns exec "$subnet_name" iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # Allow loopback
    ip netns exec "$subnet_name" iptables -A INPUT -i lo -j ACCEPT
    ip netns exec "$subnet_name" iptables -A OUTPUT -o lo -j ACCEPT
    
    # Apply inbound rules
    local inbound_count=$(jq '.inbound | length' "$policy_file")
    if [[ "$inbound_count" -gt 0 ]]; then
        log_info "Applying $inbound_count inbound rule(s)..."
        
        for ((i=0; i<inbound_count; i++)); do
            local rule=$(jq ".inbound[$i]" "$policy_file")
            local protocol=$(echo "$rule" | jq -r '.protocol')
            local port=$(echo "$rule" | jq -r '.port // empty')
            local source=$(echo "$rule" | jq -r '.source // "0.0.0.0/0"')
            local action=$(echo "$rule" | jq -r '.action')
            local desc=$(echo "$rule" | jq -r '.description // empty')
            
            # Build iptables rule
            local cmd="iptables -A INPUT"
            
            if [[ "$protocol" != "all" ]]; then
                cmd="$cmd -p $protocol"
            fi
            
            if [[ -n "$port" ]]; then
                cmd="$cmd --dport $port"
            fi
            
            if [[ "$source" != "0.0.0.0/0" ]]; then
                cmd="$cmd -s $source"
            fi
            
            cmd="$cmd -j $action"
            
            # Apply in namespace
            ip netns exec "$subnet_name" $cmd
            
            log_info "  ✓ $desc"
        done
    fi
    
    # Apply outbound rules
    local outbound_count=$(jq '.outbound | length' "$policy_file")
    if [[ "$outbound_count" -gt 0 ]]; then
        log_info "Applying $outbound_count outbound rule(s)..."
        
        for ((i=0; i<outbound_count; i++)); do
            local rule=$(jq ".outbound[$i]" "$policy_file")
            local protocol=$(echo "$rule" | jq -r '.protocol')
            local port=$(echo "$rule" | jq -r '.port // empty')
            local destination=$(echo "$rule" | jq -r '.destination // "0.0.0.0/0"')
            local action=$(echo "$rule" | jq -r '.action')
            local desc=$(echo "$rule" | jq -r '.description // empty')
            
            # Build iptables rule
            local cmd="iptables -A OUTPUT"
            
            if [[ "$protocol" != "all" ]]; then
                cmd="$cmd -p $protocol"
            fi
            
            if [[ -n "$port" ]]; then
                cmd="$cmd --dport $port"
            fi
            
            if [[ "$destination" != "0.0.0.0/0" ]]; then
                cmd="$cmd -d $destination"
            fi
            
            cmd="$cmd -j $action"
            
            # Apply in namespace
            ip netns exec "$subnet_name" $cmd
            
            log_info "  ✓ $desc"
        done
    fi
    
    log_success "Security group '$sg_name' applied to '$subnet_name'"
    
    # Store metadata
    mkdir -p /var/lib/vpcctl/security-groups
    echo "$sg_name" > "/var/lib/vpcctl/security-groups/${subnet_name}.sg"
    cp "$policy_file" "/var/lib/vpcctl/security-groups/${subnet_name}.json"
    
    return 0
}

# Remove security group from subnet
remove_security_group() {
    local subnet_name=$1
    
    if [[ -z "$subnet_name" ]]; then
        log_error "Subnet name is required"
        return 1
    fi
    
    if ! netns_exists "$subnet_name"; then
        log_error "Subnet '$subnet_name' does not exist"
        return 1
    fi
    
    log_info "Removing security group from '$subnet_name'..."
    
    # Flush all rules
    ip netns exec "$subnet_name" iptables -F INPUT
    ip netns exec "$subnet_name" iptables -F OUTPUT
    ip netns exec "$subnet_name" iptables -F FORWARD
    
    # Set permissive policies
    ip netns exec "$subnet_name" iptables -P INPUT ACCEPT
    ip netns exec "$subnet_name" iptables -P OUTPUT ACCEPT
    ip netns exec "$subnet_name" iptables -P FORWARD ACCEPT
    
    # Remove metadata
    rm -f "/var/lib/vpcctl/security-groups/${subnet_name}.sg"
    rm -f "/var/lib/vpcctl/security-groups/${subnet_name}.json"
    
    log_success "Security group removed from '$subnet_name'"
    return 0
}

# List all security groups
list_security_groups() {
    log_info "Applied Security Groups:"
    echo ""
    
    if [[ ! -d /var/lib/vpcctl/security-groups ]] || [[ -z "$(ls -A /var/lib/vpcctl/security-groups/*.sg 2>/dev/null)" ]]; then
        echo "  No security groups applied"
        return 0
    fi
    
    printf "  %-20s %-20s %-30s\n" "SUBNET" "SECURITY GROUP" "POLICY FILE"
    printf "  %-20s %-20s %-30s\n" "------" "--------------" "-----------"
    
    for sg_file in /var/lib/vpcctl/security-groups/*.sg; do
        if [[ -f "$sg_file" ]]; then
            local subnet=$(basename "$sg_file" .sg)
            local sg_name=$(cat "$sg_file")
            local policy="/var/lib/vpcctl/security-groups/${subnet}.json"
            printf "  %-20s %-20s %-30s\n" "$subnet" "$sg_name" "$policy"
        fi
    done
}

# Show security group rules for a subnet
show_security_group() {
    local subnet_name=$1
    
    if [[ -z "$subnet_name" ]]; then
        log_error "Subnet name is required"
        return 1
    fi
    
    if ! netns_exists "$subnet_name"; then
        log_error "Subnet '$subnet_name' does not exist"
        return 1
    fi
    
    log_info "Security Group Rules for '$subnet_name':"
    echo ""
    
    echo "INPUT chain:"
    ip netns exec "$subnet_name" iptables -L INPUT -n -v --line-numbers
    
    echo ""
    echo "OUTPUT chain:"
    ip netns exec "$subnet_name" iptables -L OUTPUT -n -v --line-numbers
    
    return 0
}

# Test security group rules
test_security_group() {
    local subnet_name=$1
    local target_ip=$2
    local port=${3:-80}
    
    if [[ -z "$subnet_name" ]] || [[ -z "$target_ip" ]]; then
        log_error "Usage: test_security_group <subnet_name> <target_ip> [port]"
        return 1
    fi
    
    if ! netns_exists "$subnet_name"; then
        log_error "Subnet '$subnet_name' does not exist"
        return 1
    fi
    
    log_info "Testing security group rules for '$subnet_name'..."
    echo ""
    
    # Test ping (ICMP)
    log_info "Test 1: ICMP (ping) to $target_ip"
    if ip netns exec "$subnet_name" ping -c 2 -W 2 "$target_ip" > /dev/null 2>&1; then
        log_success "✓ ICMP allowed"
    else
        log_warn "✗ ICMP blocked or target unreachable"
    fi
    
    # Test TCP connection (if nc available)
    if command -v nc &> /dev/null; then
        echo ""
        log_info "Test 2: TCP port $port to $target_ip"
        if ip netns exec "$subnet_name" timeout 3 nc -zv "$target_ip" "$port" 2>&1 | grep -q "succeeded"; then
            log_success "✓ TCP port $port allowed"
        else
            log_warn "✗ TCP port $port blocked or target unreachable"
        fi
    fi
    
    return 0
}
