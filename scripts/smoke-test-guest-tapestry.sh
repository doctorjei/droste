#!/usr/bin/env bash
# Smoke test for droste-tapestry — runs inside the guest.
#
# Verifies Phase 4 additions only (testing, benchmarking, security, observability).
# Phase 1-3 checks are in their respective guest smoke test scripts.
#
# Usage:
#   sudo ./smoke-test-guest-tapestry.sh
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

echo "droste-tapestry smoke test (guest)"
echo "==================================="
echo ""

# ── Virtual networking ───────────────────────────────────────────────
echo "Virtual networking:"
check "ovs-vsctl available"           "command -v ovs-vsctl"
echo ""

# ── Packet analysis ──────────────────────────────────────────────────
echo "Packet analysis:"
check "tshark available"              "command -v tshark"
check "tcpreplay available"           "command -v tcpreplay"
echo ""

# ── Network scanning ─────────────────────────────────────────────────
echo "Network scanning:"
check "nmap available"                "command -v nmap"
check "arp-scan available"            "test -x /usr/sbin/arp-scan"
echo ""

# ── ARM emulation ─────────────────────────────────────────────────────
echo "ARM emulation:"
check "qemu-system-arm available"     "command -v qemu-system-arm"
echo ""

# ── Load balancing ────────────────────────────────────────────────────
echo "Load balancing:"
check "haproxy available"             "test -x /usr/sbin/haproxy"
echo ""

# ── Hardware management ───────────────────────────────────────────────
echo "Hardware management:"
check "ipmitool available"            "command -v ipmitool"
echo ""

# ── Benchmarking ──────────────────────────────────────────────────────
echo "Benchmarking:"
check "fio available"                 "command -v fio"
check "stress-ng available"           "command -v stress-ng"
check "ab available"                  "command -v ab"
check "iperf3 available"              "command -v iperf3"
echo ""

# ── Disk/storage tools ────────────────────────────────────────────────
echo "Disk/storage tools:"
check "sg_inq available"              "command -v sg_inq"
check "smartctl available"            "test -x /usr/sbin/smartctl"
check "blktrace available"            "test -x /usr/sbin/blktrace"
check "xorriso available"             "command -v xorriso"
echo ""

# ── Routing ───────────────────────────────────────────────────────────
echo "Routing:"
check "bird available"                "test -x /usr/sbin/bird"
echo ""

# ── Container ecosystem ───────────────────────────────────────────────
echo "Container ecosystem:"
check "buildah available"             "command -v buildah"
check "skopeo available"              "command -v skopeo"
echo ""

# ── Observability ─────────────────────────────────────────────────────
echo "Observability:"
check "prometheus-node-exporter available" "test -x /usr/bin/prometheus-node-exporter"
check "lnav available"                "command -v lnav"
echo ""

# ── Database clients ──────────────────────────────────────────────────
echo "Database clients:"
check "psql available"                "command -v psql"
check "redis-cli available"           "command -v redis-cli"
echo ""

# ── Security ──────────────────────────────────────────────────────────
echo "Security:"
check "fail2ban-client available"     "command -v fail2ban-client"
check "lynis available"               "test -x /usr/sbin/lynis"
check "aa-enforce available"          "test -x /usr/sbin/aa-enforce"
check "aide available"                "command -v aide"
check "auditctl available"            "test -x /usr/sbin/auditctl"
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
