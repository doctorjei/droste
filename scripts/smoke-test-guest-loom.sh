#!/usr/bin/env bash
# Smoke test for droste-loom — runs inside the guest.
#
# Verifies Phase 5 additions only (C/C++ development toolchain).
# Phase 1-4 checks are in their respective guest smoke test scripts.
#
# Usage:
#   sudo ./smoke-test-guest-loom.sh
set -euo pipefail

# ── Test framework ──────────────────────────────────────────────────
PASS=0
FAIL=0
ERRORS=()

check() {
    local description="$1"
    shift
    if eval "$@" &>/dev/null; then
        echo "  + $description"
        PASS=$((PASS + 1))
    else
        echo "  - FAIL: $description"
        ERRORS+=("$description")
        FAIL=$((FAIL + 1))
    fi
}

echo "droste-loom smoke test (guest)"
echo "==============================="
echo ""

# ── Compilers ───────────────────────────────────────────────────────
echo "Compilers:"
check "gcc available"                   "command -v gcc"
check "g++ available"                   "command -v g++"
check "make available"                  "command -v make"
echo ""

# ── Build systems ───────────────────────────────────────────────────
echo "Build systems:"
check "cmake available"                 "command -v cmake"
check "autoconf available"              "command -v autoconf"
check "automake available"              "command -v automake"
check "pkg-config available"            "command -v pkg-config"
check "ninja available"                 "command -v ninja"
echo ""

# ── Debugging ───────────────────────────────────────────────────────
echo "Debugging:"
check "gdb available"                   "command -v gdb"
check "valgrind available"              "command -v valgrind"
echo ""

# ── Utilities ───────────────────────────────────────────────────────
echo "Utilities:"
check "ccache available"                "command -v ccache"
check "bear available"                  "command -v bear"
check "libtool available"               "command -v libtool"
echo ""

# ── Summary ───────────────────────────────────────────────────────────
echo "==============================="
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
