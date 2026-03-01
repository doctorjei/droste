#!/usr/bin/env bash
# Smoke test for droste-fabric — runs inside the guest.
#
# Verifies Phase 3 additions only (HA, storage, cluster).
# Phase 1 checks are in smoke-test-guest.sh, Phase 2 in smoke-test-guest-full.sh.
#
# Usage:
#   sudo ./smoke-test-guest-fabric.sh
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

echo "droste-fabric smoke test (guest)"
echo "================================="
echo ""

# ── DRBD ────────────────────────────────────────────────────────────
echo "DRBD:"
check "drbdadm available"             "test -x /usr/sbin/drbdadm"
check "drbd module configured"        "grep -q 'drbd' /etc/modules-load.d/droste.conf"
echo ""

# ── Pacemaker/HA ────────────────────────────────────────────────────
echo "Pacemaker/HA:"
check "crm_mon available"             "test -x /usr/sbin/crm_mon"
check "pcs available"                 "test -x /usr/sbin/pcs"
check "resource agents installed"     "test -d /usr/lib/ocf/resource.d"
check "sbd available"                 "test -x /usr/sbin/sbd"
check "fence_virsh available"         "test -x /usr/sbin/fence_virsh"
check "keepalived available"          "test -x /usr/sbin/keepalived"
echo ""

# ── Cluster ─────────────────────────────────────────────────────────
echo "Cluster:"
check "dlm_controld available"        "test -x /usr/sbin/dlm_controld"
echo ""

# ── iSCSI ───────────────────────────────────────────────────────────
echo "iSCSI:"
check "iscsiadm available"            "test -x /usr/sbin/iscsiadm"
check "targetcli available"           "command -v targetcli"
echo ""

# ── Storage ─────────────────────────────────────────────────────────
echo "Storage:"
check "ceph available"                "command -v ceph"
check "rbd available"                 "command -v rbd"
check "multipath available"           "test -x /usr/sbin/multipathd"
echo ""

# ── Networking ────────────────────────────────────────────────────────
echo "Networking:"
check "ebtables available"            "test -x /usr/sbin/ebtables"
echo ""

# ── PXE ───────────────────────────────────────────────────────────────
echo "PXE:"
check "syslinux files installed"     "test -d /usr/lib/syslinux"
echo ""

# ── System ────────────────────────────────────────────────────────────
echo "System:"
check "numactl available"            "command -v numactl"
echo ""


# ── Summary ─────────────────────────────────────────────────────────
echo "================================="
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
