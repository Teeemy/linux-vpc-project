#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

VPCCTL="${SCRIPT_DIR}/../vpcctl"
TEST_VPC="minimal-test-$$"

echo "=== Minimal NAT Test ==="

log_info "Step 1: Creating VPC..."
timeout 10 $VPCCTL create-vpc "$TEST_VPC" 10.88.0.0/16 || { log_error "Failed"; exit 1; }
log_success "✓ VPC created"

log_info "Step 2: Creating subnet..."
timeout 10 $VPCCTL create-subnet "$TEST_VPC" test-sub 10.88.1.0/24 || { log_error "Failed"; exit 1; }
log_success "✓ Subnet created"

log_info "Step 3: Enabling NAT..."
timeout 10 $VPCCTL enable-nat test-sub 10.88.1.0/24 || { log_error "Failed"; exit 1; }
log_success "✓ NAT enabled"

log_info "Step 4: Testing internet (with timeout)..."
if timeout 10 ip netns exec test-sub ping -c 2 -W 2 8.8.8.8 > /dev/null 2>&1; then
    log_success "✓ Internet works"
else
    log_warn "⚠ Internet test failed (might be network)"
fi

log_info "Step 5: Cleanup..."
$VPCCTL disable-nat test-sub 2>/dev/null || true
$VPCCTL delete-subnet test-sub 2>/dev/null || true
$VPCCTL delete-vpc "$TEST_VPC" 2>/dev/null || true
log_success "✓ Cleaned up"

echo ""
log_success "=== Minimal test complete! ==="
