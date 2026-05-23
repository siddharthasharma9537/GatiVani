#!/usr/bin/env bash
# GatiVani test runner
#
# Usage:
#   scripts/run_tests.sh                # Run all tests
#   scripts/run_tests.sh unit           # Only service unit tests
#   scripts/run_tests.sh widget         # Only widget tests
#   scripts/run_tests.sh screen         # Only screen widget tests
#   scripts/run_tests.sh integration    # Only integration scenarios
#   scripts/run_tests.sh coverage       # Full suite with coverage HTML report
#
# Requirements:
#   * Flutter SDK on PATH (>=3.0.0)
#   * `lcov` for HTML coverage report (brew install lcov)

set -euo pipefail

# Resolve repo root regardless of where this script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

CMD="${1:-all}"

run_section() {
  local label="$1"; shift
  echo ""
  echo "=========================================="
  echo "  $label"
  echo "=========================================="
  "$@"
}

case "$CMD" in
  unit)
    run_section "Service unit tests" \
      flutter test test/services/
    ;;
  widget)
    run_section "Widget tests" \
      flutter test test/widgets/
    ;;
  screen)
    run_section "Screen widget tests" \
      flutter test test/screens/
    ;;
  integration)
    run_section "Integration tests" \
      flutter test test/integration/
    ;;
  coverage)
    run_section "Full suite with coverage" \
      flutter test --coverage
    if command -v genhtml >/dev/null 2>&1; then
      echo ""
      echo "Generating HTML coverage report..."
      genhtml coverage/lcov.info -o coverage/html --quiet
      echo "Report: coverage/html/index.html"
    else
      echo ""
      echo "Skipping HTML report: install lcov (brew install lcov) to enable."
    fi
    ;;
  all|"")
    run_section "Service unit tests" flutter test test/services/
    run_section "Widget tests"        flutter test test/widgets/
    run_section "Screen widget tests" flutter test test/screens/
    run_section "Integration tests"   flutter test test/integration/
    ;;
  *)
    echo "Unknown command: $CMD" >&2
    echo "Usage: $0 [unit|widget|screen|integration|coverage|all]" >&2
    exit 1
    ;;
esac
