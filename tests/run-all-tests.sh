#!/bin/bash
# tests/run-all-tests.sh - Run all test suites

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/utils.sh"

TESTS=(
    "test-basic.sh"
    "test-routing.sh"
    "test-nat.sh"
    "test-isolation.sh"
    "test-peering.sh"
    "test-firewall.sh"
)

PASSED=0
FAILED=0
SKIPPED=0

echo ""
log_info "╔═══════════════════════════════════════════════════════╗"
log_info "║            VPCCTL FULL TEST SUITE                     ║"
log_info "╚═══════════════════════════════════════════════════════╝"
echo ""

for test in "${TESTS[@]}"; do
    log_info "Running: $test"
    echo ""
    
    if [[ -f "${SCRIPT_DIR}/${test}" ]]; then
        if bash "${SCRIPT_DIR}/${test}"; then
            ((PASSED++))
            log_success "✓ $test passed"
        else
            exit_code=$?
            if [[ $exit_code -eq 0 ]]; then
                ((SKIPPED++))
                log_warn "⊘ $test skipped (not implemented)"
            else
                ((FAILED++))
                log_error "✗ $test failed"
            fi
        fi
    else
        log_warn "Test file not found: $test"
        ((SKIPPED++))
    fi
    
    echo ""
    echo "─────────────────────────────────────────────────────────"
    echo ""
done

# Final summary
echo ""
log_info "╔═══════════════════════════════════════════════════════╗"
log_info "║              TEST SUITE SUMMARY                       ║"
log_info "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "  Total Tests:    ${#TESTS[@]}"
echo "  ✓ Passed:       $PASSED"
echo "  ✗ Failed:       $FAILED"
echo "  ⊘ Skipped:      $SKIPPED"
echo ""

if [[ $FAILED -gt 0 ]]; then
    log_error "Some tests failed!"
    exit 1
else
    log_success "All implemented tests passed!"
    exit 0
fi