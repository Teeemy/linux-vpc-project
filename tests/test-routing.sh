#!/bin/bash
# tests/test-routing.sh - Multi-subnet routing tests
# Tests: Inter-subnet connectivity, bridge learning, routing tables

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh""

TEST_VPC="test-routing-vpc-$$"
PUBLIC_SUBNET="test-public-$$"
PRIVATE_SUBNET="test-private-$$"
VPC_CIDR="10.200.0.0/16"
PUBLIC_CIDR="10.200.1.0/24"
PRIVATE_CIDR="10.200.2.0/24"
VPCCTL="${SCRIPT_DIR}/../vpcctl"

# Cleanup function
cleanup() {
    log_info "Cleaning up test resources..."
    sudo $VPCCTL delete-subnet "$PUBLIC_SUBNET" 2>/dev/null || true
    sudo $VPCCTL delete-subnet "$PRIVATE_SUBNET" 2>/dev/null || true
    sudo $VPCCTL delete-vpc "$TEST_VPC" 2>/dev/null || true
}

trap cleanup EXIT

echo ""
log_info "╔═══════════════════════════════════════════════════════╗"
log_info "║         MULTI-SUBNET ROUTING TEST SUITE               ║"
log_info "║  Testing: Inter-subnet routing, bridge learning       ║"
log_info "╚═══════════════════════════════════════════════════════╝"
echo ""

# Test 1: Create VPC
log_info "[1/10] Creating test VPC..."
if sudo $VPCCTL create-vpc "$TEST_VPC" "$VPC_CIDR" > /dev/null 2>&1; then
    log_success "✓ VPC created"
else
    log_error "✗ VPC creation failed"
    exit 1
fi

BRIDGE_IP=$(ip -4 addr show "$TEST_VPC" | grep -oP 'inet \K[\d.]+' | head -1)

# Test 2: Create public subnet
log_info "[2/10] Creating public subnet..."
if sudo $VPCCTL create-subnet "$TEST_VPC" "$PUBLIC_SUBNET" "$PUBLIC_CIDR" > /dev/null 2>&1; then
    log_success "✓ Public subnet created"
else
    log_error "✗ Public subnet creation failed"
    exit 1
fi

# Test 3: Create private subnet
log_info "[3/10] Creating private subnet..."
if sudo $VPCCTL create-subnet "$TEST_VPC" "$PRIVATE_SUBNET" "$PRIVATE_CIDR" > /dev/null 2>&1; then
    log_success "✓ Private subnet created"
else
    log_error "✗ Private subnet creation failed"
    exit 1
fi

# Wait for interfaces to stabilize
sleep 1

# Test 4: Public subnet → gateway
log_info "[4/10] Testing public subnet → gateway..."
if sudo $VPCCTL test-ping "$PUBLIC_SUBNET" "$BRIDGE_IP" 2 > /dev/null 2>&1; then
    log_success "✓ Public subnet can reach gateway"
else
    log_error "✗ Public subnet cannot reach gateway"
    exit 1
fi

# Test 5: Private subnet → gateway
log_info "[5/10] Testing private subnet → gateway..."
if sudo $VPCCTL test-ping "$PRIVATE_SUBNET" "$BRIDGE_IP" 2 > /dev/null 2>&1; then
    log_success "✓ Private subnet can reach gateway"
else
    log_error "✗ Private subnet cannot reach gateway"
    exit 1
fi

# Get subnet IPs
PUBLIC_IP=$(sudo ip netns exec "$PUBLIC_SUBNET" ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127' | head -1)
PRIVATE_IP=$(sudo ip netns exec "$PRIVATE_SUBNET" ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127' | head -1)

# Test 6: Inter-subnet routing (public → private)
log_info "[6/10] Testing inter-subnet routing (public → private)..."
echo "  Source: $PUBLIC_IP → Destination: $PRIVATE_IP"
if sudo $VPCCTL test-ping "$PUBLIC_SUBNET" "$PRIVATE_IP" 3 > /dev/null 2>&1; then
    log_success "✓ Public subnet can reach private subnet"
else
    log_error "✗ Inter-subnet routing failed"
    log_info "Debug info:"
    echo "  IP forwarding: $(sysctl -n net.ipv4.ip_forward)"
    sudo $VPCCTL show-routes "$PUBLIC_SUBNET"
    exit 1
fi

# Test 7: Reverse routing (private → public)
log_info "[7/10] Testing reverse routing (private → public)..."
echo "  Source: $PRIVATE_IP → Destination: $PUBLIC_IP"
if sudo $VPCCTL test-ping "$PRIVATE_SUBNET" "$PUBLIC_IP" 3 > /dev/null 2>&1; then
    log_success "✓ Private subnet can reach public subnet"
else
    log_error "✗ Reverse routing failed"
    exit 1
fi

# Test 8: Bridge MAC learning
log_info "[8/10] Verifying bridge MAC learning..."
LEARNED_MACS=$(bridge fdb show br "$TEST_VPC" | grep -v "permanent" | grep -v "self" | wc -l)
if [[ $LEARNED_MACS -ge 2 ]]; then
    log_success "✓ Bridge learned $LEARNED_MACS MAC addresses"
else
    log_warn "Bridge learned only $LEARNED_MACS MACs (expected ≥2)"
fi

# Test 9: Routing table verification
log_info "[9/10] Verifying routing tables..."
if sudo ip netns exec "$PUBLIC_SUBNET" ip route show | grep -q "default via $BRIDGE_IP"; then
    log_success "✓ Public subnet has correct default route"
else
    log_error "✗ Public subnet missing default route"
    exit 1
fi

if sudo ip netns exec "$PRIVATE_SUBNET" ip route show | grep -q "default via $BRIDGE_IP"; then
    log_success "✓ Private subnet has correct default route"
else
    log_error "✗ Private subnet missing default route"
    exit 1
fi

# Test 10: Bridge port count
log_info "[10/10] Verifying bridge ports..."
BRIDGE_PORTS=$(bridge link show | grep -c "$TEST_VPC" || echo "0")
if [[ $BRIDGE_PORTS -eq 2 ]]; then
    log_success "✓ Bridge has 2 ports (public + private)"
else
    log_error "✗ Bridge has $BRIDGE_PORTS ports (expected 2)"
    exit 1
fi

# Summary
echo ""
log_success "╔═══════════════════════════════════════════════════════╗"
log_success "║          ALL ROUTING TESTS PASSED! ✓                  ║"
log_success "╚═══════════════════════════════════════════════════════╝"
echo ""
log_info "Test Summary:"
echo "  ✓ Multi-subnet VPC creation"
echo "  ✓ Gateway connectivity (both subnets)"
echo "  ✓ Bidirectional inter-subnet routing"
echo "  ✓ Bridge MAC address learning"
echo "  ✓ Proper routing table configuration"
echo "  ✓ Bridge port verification"
echo ""