#!/usr/bin/env bash
# Smoke test for droste-jacquard — runs inside the guest.
#
# Verifies Phase 6 additions only (Proxmox VE environment).
# Phase 1-5 checks are in their respective guest smoke test scripts.
#
# Note: PVE kernel is not yet running during the packer build (still on
# Debian kernel), so the "PVE kernel running" check is omitted here.
# Instead we verify the Debian stock kernel was removed.
#
# Usage:
#   sudo ./smoke-test-guest-jacquard.sh
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

echo "droste-jacquard smoke test (guest)"
echo "==================================="
echo ""

# ── Debian stock kernel removed ────────────────────────────────────
echo "Kernel:"
check "Debian stock kernel removed"       "! dpkg -l linux-image-amd64 2>/dev/null | grep -q ^ii"
echo ""

# ── PVE CLI tools ──────────────────────────────────────────────────
echo "PVE CLI tools:"
check "pveversion available"              "command -v pveversion"
check "pvesh available"                   "command -v pvesh"
check "qm available"                      "test -x /usr/sbin/qm"
check "pct available"                     "test -x /usr/sbin/pct"
check "pvecm available"                   "command -v pvecm"
check "pvesm available"                   "test -x /usr/sbin/pvesm"
echo ""

# ── PVE daemons ────────────────────────────────────────────────────
echo "PVE daemons:"
check "pveproxy installed"                "test -x /usr/bin/pveproxy"
check "pvedaemon installed"               "test -x /usr/bin/pvedaemon"
echo ""

echo "ZFS:"
check "zpool available"                   "command -v zpool || test -x /usr/sbin/zpool"
check "zfs available"                     "command -v zfs || test -x /usr/sbin/zfs"
echo ""

# ── Cluster ────────────────────────────────────────────────────────
echo "Cluster:"
check "corosync available"                "test -x /usr/sbin/corosync"
check "ha-manager available"              "test -x /usr/sbin/ha-manager"
echo ""

# ── Summary ───────────────────────────────────────────────────────────
echo "==================================="
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
