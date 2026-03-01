#!/usr/bin/env bash
# Smoke test droste-tapestry additions over SSH.
#
# Verifies Phase 4 additions only (testing, benchmarking, security, observability).
# Phase 1-3 checks are in their respective smoke test scripts.
#
# Usage:
#   scripts/smoke-test-tapestry.sh
#   scripts/smoke-test-tapestry.sh --port 2222 --user agent --host localhost
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

Smoke test droste-tapestry additions over SSH.

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
echo "droste-tapestry smoke test"
echo "=========================="
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
check "arp-scan available"            "command -v arp-scan"
echo ""

# ── ARM emulation ─────────────────────────────────────────────────────
echo "ARM emulation:"
check "qemu-system-arm available"     "command -v qemu-system-arm"
echo ""

# ── Load balancing ────────────────────────────────────────────────────
echo "Load balancing:"
check "haproxy available"             "command -v haproxy"
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
check "blktrace available"            "command -v blktrace"
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
check "lynis available"               "command -v lynis"
check "aa-enforce available"          "command -v aa-enforce"
check "aide available"                "command -v aide"
check "auditctl available"            "test -x /usr/sbin/auditctl"
echo ""

# ── Summary ───────────────────────────────────────────────────────────
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
