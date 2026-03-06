#!/usr/bin/env bash
# Check download and installed sizes for tapestry tier candidates.
#
# Runs apt install --dry-run inside a running droste-fabric instance
# and parses the output for each package.
#
# Usage:
#   scripts/check-tapestry-sizes.sh --ssh-key ~/.ssh/id_ed25519
#   scripts/check-tapestry-sizes.sh --port 2222 --ssh-key ~/.ssh/id_ed25519
set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────
HOST="localhost"
PORT=2222
USER="droste"
SSH_KEY=""

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Check tapestry package sizes against a running droste-fabric instance.

Options:
  --host HOST      Guest hostname or IP (default: localhost)
  --port PORT      SSH port (default: 2222)
  --user USER      SSH user (default: droste)
  --ssh-key FILE   Path to SSH private key
  -h, --help       Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)   HOST="$2";    shift 2 ;;
        --port)   PORT="$2";    shift 2 ;;
        --user)   USER="$2";    shift 2 ;;
        --ssh-key) SSH_KEY="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "$PORT")
if [[ -n "$SSH_KEY" ]]; then
    SSH_OPTS+=(-i "$SSH_KEY")
fi

ssh_run() {
    ssh "${SSH_OPTS[@]}" "${USER}@${HOST}" "$@"
}

# ── Size formatters ────────────────────────────────────────────────
fmt_bytes() {
    local b=$1
    if (( b >= 1048576 )); then
        awk "BEGIN { printf \"%.1f MB\", $b/1048576 }"
    elif (( b >= 1024 )); then
        awk "BEGIN { printf \"%.0f kB\", $b/1024 }"
    else
        printf "%d B" "$b"
    fi
}

fmt_kib() {
    local k=$1
    if (( k >= 1024 )); then
        awk "BEGIN { printf \"%.1f MB\", $k/1024 }"
    else
        printf "%d kB" "$k"
    fi
}

# ── Package list ────────────────────────────────────────────────────
# Group A: confirmed tapestry packages
# Group B: candidates
PACKAGES=(
    # Group A
    openvswitch-switch
    tshark
    qemu-system-arm
    nmap
    haproxy
    ipmitool
    fio
    stress-ng
    sg3-utils
    bird2
    smartmontools
    apache2-utils
    iperf3
    buildah
    skopeo
    prometheus-node-exporter
    postgresql-client
    lnav
    redis-tools
    lynis
    xorriso
    apparmor-utils
    aide
    auditd
    blktrace
    arp-scan
    tcpreplay
)

# ── Update apt cache ────────────────────────────────────────────────
echo "Updating apt cache..."
ssh_run "sudo apt-get update -qq" 2>/dev/null

# ── Header ──────────────────────────────────────────────────────────
printf "%-30s %12s %12s %8s\n" "Package" "Download" "Installed" "New pkgs"
printf "%-30s %12s %12s %8s\n" "-------" "--------" "---------" "--------"

for pkg in "${PACKAGES[@]}"; do
    # Single SSH call: dry-run to find new packages, apt-cache show for sizes.
    # Returns structured lines: STATUS:, NEW:, DL: (bytes), INST: (KiB).
    result=$(ssh_run bash -s -- "$pkg" <<'REMOTE'
pkg="$1"
sim=$(sudo apt-get install -s --no-install-recommends "$pkg" 2>/dev/null)

if echo "$sim" | grep -q "is already the newest"; then
    echo "STATUS:installed"
    exit 0
fi

if echo "$sim" | grep -q "Unable to locate package"; then
    echo "STATUS:notfound"
    exit 0
fi

new_count=$(echo "$sim" | grep -oP '\d+(?= newly installed)' || echo 0)

# Get package names from Inst lines
pkgs=$(echo "$sim" | sed -n 's/^Inst \([^ ]*\) .*/\1/p')

if [ -n "$pkgs" ]; then
    # apt-cache show: Size is bytes (download), Installed-Size is KiB.
    # Dedup by package name in case multiple versions appear.
    sizes=$(apt-cache show $pkgs 2>/dev/null | awk '
        /^Package:/ { p=$2; if(seen[p]) skip=1; else { seen[p]=1; skip=0 } }
        skip { next }
        /^Size:/ { dl += $2 }
        /^Installed-Size:/ { inst += $2 }
        END { print dl+0; print inst+0 }
    ')
    dl_bytes=$(echo "$sizes" | sed -n '1p')
    inst_kib=$(echo "$sizes" | sed -n '2p')
else
    dl_bytes=0
    inst_kib=0
fi

echo "NEW:$new_count"
echo "DL:$dl_bytes"
echo "INST:$inst_kib"
REMOTE
    ) 2>/dev/null || result="STATUS:error"

    case "$result" in
        *STATUS:installed*)
            printf "%-30s %12s %12s %8s\n" "$pkg" "(installed)" "-" "-"
            continue ;;
        *STATUS:notfound*)
            printf "%-30s %12s %12s %8s\n" "$pkg" "(not found)" "-" "-"
            continue ;;
        *STATUS:error*)
            printf "%-30s %12s %12s %8s\n" "$pkg" "(error)" "-" "-"
            continue ;;
    esac

    new_count=$(echo "$result" | grep '^NEW:' | cut -d: -f2)
    dl_bytes=$(echo "$result" | grep '^DL:' | cut -d: -f2)
    inst_kib=$(echo "$result" | grep '^INST:' | cut -d: -f2)

    dl_size=$(fmt_bytes "${dl_bytes:-0}")
    inst_size=$(fmt_kib "${inst_kib:-0}")

    printf "%-30s %12s %12s %8s\n" "$pkg" "$dl_size" "$inst_size" "${new_count:-0}"
done

echo ""
echo "Done. All sizes are incremental (on top of fabric)."
