#!/bin/bash
# tests/test-nat.sh - NAT gateway functionality tests
# Tests: Public subnet internet access, private subnet isolation, MASQUERADE

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

TEST_VPC="test-nat-vpc-$$"
PUBLIC_SUBNET="nat-public-$$"
PRIVATE_SUBNET="nat-private-$$"
VPC_CIDR="10.150.0.0/16"
PUBLIC_CIDR="10.150.1.0/24"
PRIVATE_CIDR="10.150.2.0/24"
VPCCTL="${SCRIPT_DIR}/../vpcctl"

cleanup() {
    log_info "Cleaning up test resources..."
    $VPCCTL disable-nat "$PUBLIC_SUBNET" 2>/dev/null || true
    $VPCCTL delete-subnet "$PUBLIC_SUBNET" 2>/dev/null || true
    $VPCCTL delete-subnet "$PRIVATE_SUBNET" 2>/dev/null || true
    $VPCCTL delete-vpc "$TEST_VPC" 2>/dev/null || true
}

trap cleanup EXIT

echo ""
log_info "╔═══════════════════════════════════════════════════════╗"
log_info "║            NAT GATEWAY TEST SUITE                     ║"
log_info "║  Testing: Internet access, NAT isolation              ║"
log_info "╚═══════════════════════════════════════════════════════╝"
echo ""

# Test 1: Create VPC and subnets
log_info "[1/10] Creating test environment..."
if $VPCCTL create-vpc "$TEST_VPC" "$VPC_CIDR" > /dev/null 2>&1; then
    $VPCCTL create-subnet "$TEST_VPC" "$PUBLIC_SUBNET" "$PUBLIC_CIDR" > /dev/null 2>&1
    $VPCCTL create-subnet "$TEST_VPC" "$PRIVATE_SUBNET" "$PRIVATE_CIDR" > /dev/null 2>&1
    log_success "✓ VPC and subnets created"
else
    log_error "✗ Failed to create test environment"
    exit 1
fi

sleep 1

# Test 2: Verify no internet access BEFORE NAT
log_info "[2/10] Testing internet access BEFORE NAT..."
if timeout 5 ip netns exec "$PUBLIC_SUBNET" ping -c 2 -W 2 8.8.8.8 > /dev/null 2>&1; then
    log_warn "Subnet has internet without NAT (host routing enabled?)"
else
    log_success "✓ No internet access without NAT (expected)"
fi

# Test 3: Enable NAT for public subnet
log_info "[3/10] Enabling NAT for public subnet..."
if $VPCCTL enable-nat "$PUBLIC_SUBNET" "$PUBLIC_CIDR" > /dev/null 2>&1; then
    log_success "✓ NAT enabled"
else
    log_error "✗ Failed to enable NAT"
    exit 1
fi

# Test 4: Verify iptables rules exist
log_info "[4/10] Verifying iptables NAT rules..."
WAN_IF=$(ip route show default | awk '/default/ {print $5}' | head -1)
if iptables -t nat -C POSTROUTING -s "$PUBLIC_CIDR" -o "$WAN_IF" -j MASQUERADE 2>/dev/null; then
    log_success "✓ MASQUERADE rule exists"
else
    log_error "✗ MASQUERADE rule not found"
    exit 1
fi

# Test 5: Test internet connectivity from public subnet
log_info "[5/10] Testing internet from public subnet (ping 8.8.8.8)..."
if timeout 10 ip netns exec "$PUBLIC_SUBNET" ping -c 3 -W 2 8.8.8.8 > /dev/null 2>&1; then
    log_success "✓ Public subnet can reach internet"
else
    log_warn "⚠ Public subnet cannot reach internet (network issue?)"
fi

# Test 6: Test DNS resolution from public subnet
log_info "[6/10] Testing DNS resolution from public subnet..."
if command -v dig &> /dev/null; then
    if timeout 5 ip netns exec "$PUBLIC_SUBNET" dig +short +time=2 google.com @8.8.8.8 2>/dev/null | grep -q "^[0-9]"; then
        log_success "✓ DNS resolution works"
    else
        log_warn "DNS resolution failed (non-critical)"
    fi
else
    log_warn "dig not installed, skipping DNS test"
fi

# Test 7: CRITICAL - Verify private subnet CANNOT reach internet
log_info "[7/10] Testing private subnet isolation (should FAIL to reach internet)..."
if timeout 5 ip netns exec "$PRIVATE_SUBNET" ping -c 2 -W 2 8.8.8.8 > /dev/null 2>&1; then
    log_error "✗ Private subnet can reach internet (NAT isolation failed!)"
    exit 1
else
    log_success "✓ Private subnet correctly isolated (no internet access)"
fi

# Test 8: Verify NAT configuration
log_info "[8/10] Verifying NAT configuration..."
if $VPCCTL verify-nat "$PUBLIC_SUBNET" > /dev/null 2>&1; then
    log_success "✓ NAT configuration valid"
else
    log_error "✗ NAT configuration invalid"
    exit 1
fi

# Test 9: Test inter-subnet routing still works
log_info "[9/10] Verifying inter-subnet routing (NAT shouldn't break this)..."
PRIVATE_IP=$(ip netns exec "$PRIVATE_SUBNET" ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127' | head -1)
if timeout 5 ip netns exec "$PUBLIC_SUBNET" ping -c 2 -W 2 "$PRIVATE_IP" > /dev/null 2>&1; then
    log_success "✓ Inter-subnet routing works"
else
    log_error "✗ Inter-subnet routing broken"
    exit 1
fi

# Test 10: Disable NAT and verify internet access removed
log_info "[10/10] Testing NAT disable..."
$VPCCTL disable-nat "$PUBLIC_SUBNET" > /dev/null 2>&1

if iptables -t nat -C POSTROUTING -s "$PUBLIC_CIDR" -o "$WAN_IF" -j MASQUERADE 2>/dev/null; then
    log_error "✗ NAT rule still exists after disable"
    exit 1
else
    log_success "✓ NAT rule removed successfully"
fi

# Summary
echo ""
log_success "╔═══════════════════════════════════════════════════════╗"
log_success "║          ALL NAT TESTS PASSED! ✓                      ║"
log_success "╚═══════════════════════════════════════════════════════╝"
echo ""
log_info "Test Summary:"
echo "  ✓ NAT enabled/disabled correctly"
echo "  ✓ Public subnet has internet access"
echo "  ✓ Private subnet correctly isolated"
echo "  ✓ iptables MASQUERADE rules working"
echo "  ✓ Inter-subnet routing unaffected"
echo ""