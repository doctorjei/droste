#!/usr/bin/env bash
# Smoke test droste-fabric additions over SSH.
#
# Verifies Phase 3 additions only (HA, storage, cluster).
# Phase 1 checks are in smoke-test.sh, Phase 2 in smoke-test-yarn.sh.
#
# Usage:
#   scripts/smoke-test-fabric.sh
#   scripts/smoke-test-fabric.sh --port 2222 --user agent --host localhost
set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────
HOST="localhost"
PORT=2222
USER="agent"
SSH_KEY=""

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Smoke test droste-fabric additions over SSH.

Options:
  --host HOST      Guest hostname or IP (default: localhost)
  --port PORT      SSH port (default: 2222)
  --user USER      SSH user (default: agent)
  --ssh-key FILE   Path to SSH private key (default: ssh default)
  -h, --help       Show this help message
EOF
}

# ── Parse arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)    HOST="$2"; shift 2 ;;
        --port)    PORT="$2"; shift 2 ;;
        --user)    USER="$2"; shift 2 ;;
        --ssh-key) SSH_KEY="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)         echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# ── Build SSH command ───────────────────────────────────────────────
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
SSH_OPTS+=(-p "$PORT")
if [[ -n "$SSH_KEY" ]]; then
    SSH_OPTS+=(-i "$SSH_KEY")
fi

ssh_run() {
    ssh "${SSH_OPTS[@]}" "${USER}@${HOST}" "$@"
}

# ── Test framework ──────────────────────────────────────────────────
PASS=0
FAIL=0
ERRORS=()

check() {
    local description="$1"
    shift
    if ssh_run "$@" &>/dev/null; then
        echo "  + $description"
        PASS=$((PASS + 1))
    else
        echo "  - FAIL: $description"
        ERRORS+=("$description")
        FAIL=$((FAIL + 1))
    fi
}

# ── Connectivity ────────────────────────────────────────────────────
echo "droste-fabric smoke test"
echo "========================"
echo ""
echo "Target: ${USER}@${HOST}:${PORT}"
echo ""

echo "Connectivity:"
if ! ssh_run true; then
    echo "  - FAIL: cannot connect to ${USER}@${HOST}:${PORT}"
    echo ""
    echo "Results: 0 passed, 1 failed"
    exit 1
fi
echo "  + SSH connection"
PASS=1
echo ""

# ── DRBD ────────────────────────────────────────────────────────────
echo "DRBD:"
check "drbdadm available"             "test -x /usr/sbin/drbdadm"
check "drbd module configured"        "grep -q 'drbd' /etc/modules-load.d/droste.conf"
echo ""

# ── Pacemaker/HA ────────────────────────────────────────────────────
echo "Pacemaker/HA:"
check "crm_mon available"             "sudo crm_mon --version"
check "pcs available"                 "test -x /usr/sbin/pcs"
check "resource agents installed"     "test -d /usr/lib/ocf/resource.d"
check "sbd available"                 "test -x /usr/sbin/sbd"
check "fence_virsh available"         "test -x /usr/sbin/fence_virsh"
check "keepalived available"          "test -x /usr/sbin/keepalived"
echo ""

# ── Cluster ─────────────────────────────────────────────────────────
echo "Cluster:"
check "dlm_controld available"        "test -x /usr/sbin/dlm_controld"
check "clush available"               "clush --version"
echo ""

# ── iSCSI ───────────────────────────────────────────────────────────
echo "iSCSI:"
check "iscsiadm available"            "test -x /usr/sbin/iscsiadm"
check "targetcli available"           "sudo targetcli ls"
echo ""

# ── Storage ─────────────────────────────────────────────────────────
echo "Storage:"
check "ceph available"                "ceph --version"
check "rbd available"                 "rbd --version"
check "multipath available"           "test -x /usr/sbin/multipathd"
echo ""

# ── Networking ────────────────────────────────────────────────────────
echo "Networking:"
check "ebtables available"            "test -x /usr/sbin/ebtables"
echo ""

# ── PXE ───────────────────────────────────────────────────────────────
echo "PXE:"
check "pxelinux.0 exists"            "test -f /usr/lib/PXELINUX/pxelinux.0 || test -f /usr/lib/syslinux/modules/bios/ldlinux.c32"
echo ""

# ── System ────────────────────────────────────────────────────────────
echo "System:"
check "numactl available"            "numactl --show"
echo ""

# ── Summary ─────────────────────────────────────────────────────────
echo "================================"
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
