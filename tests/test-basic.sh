#!/bin/bash
# tests/test-basic.sh - Basic VPC and subnet connectivity tests
# Tests: VPC creation, single subnet, gateway connectivity, cleanup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh""

TEST_VPC="test-basic-vpc-$$"
TEST_SUBNET="test-basic-subnet-$$"
VPC_CIDR="10.100.0.0/16"
SUBNET_CIDR="10.100.1.0/24"
VPCCTL="${SCRIPT_DIR}/../vpcctl"

# Cleanup function
cleanup() {
    log_info "Cleaning up test resources..."
    sudo $VPCCTL delete-subnet "$TEST_SUBNET" 2>/dev/null || true
    sudo $VPCCTL delete-vpc "$TEST_VPC" 2>/dev/null || true
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Start tests
echo ""
log_info "╔═══════════════════════════════════════════════════════╗"
log_info "║         BASIC CONNECTIVITY TEST SUITE                 ║"
log_info "║  Testing: VPC creation, subnet, gateway connectivity  ║"
log_info "╚═══════════════════════════════════════════════════════╝"
echo ""

# Test 1: VPC Creation
log_info "[1/8] Testing VPC creation..."
if sudo $VPCCTL create-vpc "$TEST_VPC" "$VPC_CIDR" > /dev/null 2>&1; then
    log_success "✓ VPC '$TEST_VPC' created successfully"
else
    log_error "✗ VPC creation failed"
    exit 1
fi

# Test 2: Verify bridge device exists
log_info "[2/8] Verifying bridge device..."
if ip link show "$TEST_VPC" &> /dev/null; then
    log_success "✓ Bridge device exists"
else
    log_error "✗ Bridge device not found"
    exit 1
fi

# Test 3: Verify bridge has IP address
log_info "[3/8] Verifying bridge IP assignment..."
BRIDGE_IP=$(ip -4 addr show "$TEST_VPC" | grep -oP 'inet \K[\d.]+' | head -1)
if [[ -n "$BRIDGE_IP" ]]; then
    log_success "✓ Bridge has IP: $BRIDGE_IP"
else
    log_error "✗ Bridge has no IP address"
    exit 1
fi

# Test 4: Subnet creation
log_info "[4/8] Testing subnet creation..."
if sudo $VPCCTL create-subnet "$TEST_VPC" "$TEST_SUBNET" "$SUBNET_CIDR" > /dev/null 2>&1; then
    log_success "✓ Subnet '$TEST_SUBNET' created successfully"
else
    log_error "✗ Subnet creation failed"
    exit 1
fi

# Test 5: Verify namespace exists
log_info "[5/8] Verifying network namespace..."
if ip netns list | grep -q "^${TEST_SUBNET}"; then
    log_success "✓ Network namespace exists"
else
    log_error "✗ Network namespace not found"
    exit 1
fi

# Test 6: Verify veth pair connectivity
log_info "[6/8] Testing veth pair connectivity..."
VETH_BRIDGE="veth-${TEST_SUBNET}-br"
if ip link show "$VETH_BRIDGE" &> /dev/null; then
    log_success "✓ veth pair created and connected to bridge"
else
    log_error "✗ veth pair not found"
    exit 1
fi

# Test 7: Gateway connectivity
log_info "[7/8] Testing subnet → gateway connectivity..."
if sudo ip netns exec "$TEST_SUBNET" ping -c 2 -W 2 "$BRIDGE_IP" > /dev/null 2>&1; then
    log_success "✓ Subnet can reach gateway ($BRIDGE_IP)"
else
    log_error "✗ Cannot ping gateway from subnet"
    log_info "Debug: Check IP forwarding and interface status"
    exit 1
fi

# Test 8: Loopback inside namespace
log_info "[8/8] Testing loopback interface..."
if sudo ip netns exec "$TEST_SUBNET" ping -c 2 127.0.0.1 > /dev/null 2>&1; then
    log_success "✓ Loopback working inside namespace"
else
    log_error "✗ Loopback not working"
    exit 1
fi

# Summary
echo ""
log_success "╔═══════════════════════════════════════════════════════╗"
log_success "║          ALL BASIC TESTS PASSED! ✓                    ║"
log_success "╚═══════════════════════════════════════════════════════╝"
echo ""
log_info "Test Summary:"
echo "  ✓ VPC creation and configuration"
echo "  ✓ Bridge device and IP assignment"
echo "  ✓ Subnet (namespace) creation"
echo "  ✓ veth pair connectivity"
echo "  ✓ Gateway reachability"
echo "  ✓ Loopback functionality"
echo ""
log_info "Cleanup will run automatically on exit"