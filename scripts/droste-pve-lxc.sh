#!/usr/bin/env bash
# Deploy a droste LXC image to Proxmox VE.
#
# Flattens overlay tarballs into a single rootfs and creates a PVE container.
# Run this on the Proxmox host, not the build VM.
#
# Usage:
#   droste-pve-lxc.sh fiber
#   droste-pve-lxc.sh --tarball-dir /mnt/images --start tome
#   droste-pve-lxc.sh --template-only -o /var/lib/vz/template/cache/droste-tome.tar.xz tome
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Tier chain ──────────────────────────────────────────────────────
# seed is always the base; each tier includes all layers below it
ALL_LXC_TIERS=(seed fiber sheet page tome press gutenberg)

declare -A TIER_CHAIN
TIER_CHAIN[seed]="seed"
TIER_CHAIN[fiber]="seed fiber"
TIER_CHAIN[sheet]="seed fiber sheet"
TIER_CHAIN[page]="seed fiber sheet page"
TIER_CHAIN[tome]="seed fiber sheet page tome"
TIER_CHAIN[press]="seed fiber sheet page tome press"
TIER_CHAIN[gutenberg]="seed fiber sheet page tome press gutenberg"

is_valid_tier() {
    [[ -n "${TIER_CHAIN[$1]+x}" ]]
}

# ── Defaults ────────────────────────────────────────────────────────
TARBALL_DIR="."
STORAGE="local"
CTID=""
MEMORY=512
CORES=2
BRIDGE="vmbr0"
DISK=4
HOSTNAME=""
TEMPLATE_ONLY=false
OUTPUT=""
PRIVILEGED=true
START=false
TIER=""

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <tier>

Deploy a droste LXC image to Proxmox VE.

Tiers: seed, fiber, sheet, page, tome, press, gutenberg

Options:
  -t, --tarball-dir DIR  Directory with .tar.xz files (default: .)
  -s, --storage POOL     PVE storage pool (default: local)
  -i, --ctid ID          Container ID (default: next available)
  -m, --memory MB        RAM in MB (default: 512)
  -c, --cores N          CPU cores (default: 2)
  -b, --bridge NAME      Network bridge (default: vmbr0)
  -d, --disk GB          Rootfs size in GB (default: 4)
  -n, --name NAME        Hostname (default: droste-<tier>)
      --template-only    Create flat tarball only (save to --output)
  -o, --output PATH      Output path for --template-only
      --privileged       Create privileged container (default)
      --unprivileged     Create unprivileged container
      --start            Start container after creation
  -h, --help             Show help

The script flattens overlay tarballs (seed + deltas up to the target tier)
into a single rootfs, then imports it as a PVE container template.

With --template-only, it creates the flat tarball without creating a container.
This is useful for preparing templates on a non-PVE host.

Examples:
  $(basename "$0") fiber
  $(basename "$0") --tarball-dir /mnt/images --start tome
  $(basename "$0") --template-only -o droste-tome-flat.tar.xz tome
  $(basename "$0") --storage local-lvm --unprivileged --disk 8 press
EOF
}

# ── Parse arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--tarball-dir)  TARBALL_DIR="$2"; shift 2 ;;
        -s|--storage)      STORAGE="$2"; shift 2 ;;
        -i|--ctid)         CTID="$2"; shift 2 ;;
        -m|--memory)       MEMORY="$2"; shift 2 ;;
        -c|--cores)        CORES="$2"; shift 2 ;;
        -b|--bridge)       BRIDGE="$2"; shift 2 ;;
        -d|--disk)         DISK="$2"; shift 2 ;;
        -n|--name)         HOSTNAME="$2"; shift 2 ;;
        --template-only)   TEMPLATE_ONLY=true; shift ;;
        -o|--output)       OUTPUT="$2"; shift 2 ;;
        --privileged)      PRIVILEGED=true; shift ;;
        --unprivileged)    PRIVILEGED=false; shift ;;
        --start)           START=true; shift ;;
        -h|--help)         usage; exit 0 ;;
        -*)                echo "Error: unknown option: $1" >&2; usage >&2; exit 1 ;;
        *)
            if [[ -z "$TIER" ]]; then
                TIER="$1"; shift
            else
                echo "Error: unexpected argument: $1" >&2; usage >&2; exit 1
            fi
            ;;
    esac
done

if [[ -z "$TIER" ]]; then
    echo "Error: tier is required" >&2
    usage >&2
    exit 1
fi

# ── Validate tier ───────────────────────────────────────────────────
if ! is_valid_tier "$TIER"; then
    echo "Error: unknown tier: $TIER" >&2
    echo "Valid tiers: ${ALL_LXC_TIERS[*]}" >&2
    exit 1
fi

HOSTNAME="${HOSTNAME:-droste-${TIER}}"
TARBALL_DIR="$(realpath "$TARBALL_DIR")"

# ── Prerequisites ───────────────────────────────────────────────────
if ! $TEMPLATE_ONLY; then
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "Error: must run as root on the Proxmox host" >&2
        exit 1
    fi
    for cmd in pct pvesh; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: $cmd not found. Is this a Proxmox host?" >&2
            exit 1
        fi
    done
else
    if [[ -z "$OUTPUT" ]]; then
        echo "Error: --output is required with --template-only" >&2
        exit 1
    fi
fi

# ── Validate tarballs ──────────────────────────────────────────────
layers=(${TIER_CHAIN[$TIER]})
for layer in "${layers[@]}"; do
    tarball="${TARBALL_DIR}/droste-${layer}.tar.xz"
    if [[ ! -f "$tarball" ]]; then
        echo "Error: tarball not found: $tarball" >&2
        exit 1
    fi
done

# ── Auto-assign CTID ───────────────────────────────────────────────
if ! $TEMPLATE_ONLY && [[ -z "$CTID" ]]; then
    CTID=$(pvesh get /cluster/nextid)
    echo "Auto-assigned CTID: $CTID"
fi

# ── Cleanup trap ────────────────────────────────────────────────────
TMPDIR=""
cleanup() {
    if [[ -n "$TMPDIR" && -d "$TMPDIR" ]]; then
        rm -rf "$TMPDIR"
    fi
}
trap cleanup EXIT

# ── Flatten layers ─────────────────────────────────────────────────
echo "Flattening ${#layers[@]} layers for ${TIER}..."
TMPDIR=$(mktemp -d "/tmp/droste-pve-lxc.XXXXXX")
ROOTFS="${TMPDIR}/rootfs"
mkdir -p "$ROOTFS"

for layer in "${layers[@]}"; do
    tarball="${TARBALL_DIR}/droste-${layer}.tar.xz"
    echo "  Extracting: droste-${layer}.tar.xz"
    # Whiteout devices (char 0:0) fail with mknod errors — harmless
    tar -xf "$tarball" -C "$ROOTFS" 2>/dev/null || true
done

# ── Create flat tarball ─────────────────────────────────────────────
FLAT_TARBALL="${TMPDIR}/droste-${TIER}-flat.tar.xz"
echo "Creating flat tarball..."
tar -cf "$FLAT_TARBALL" --xz -C "$ROOTFS" .
echo "Flat tarball: $(du -h "$FLAT_TARBALL" | cut -f1)"

# Free rootfs to save space
rm -rf "$ROOTFS"

# ── Template-only mode ──────────────────────────────────────────────
if $TEMPLATE_ONLY; then
    cp "$FLAT_TARBALL" "$OUTPUT"
    echo ""
    echo "Template saved to: $OUTPUT"
    echo "  Tier:   $TIER"
    echo "  Layers: ${layers[*]}"
    echo "  Size:   $(du -h "$OUTPUT" | cut -f1)"
    exit 0
fi

# ── Create container ────────────────────────────────────────────────
echo ""
echo "Creating container ${CTID} (${HOSTNAME})..."

pct_args=(
    pct create "$CTID" "$FLAT_TARBALL"
    --hostname "$HOSTNAME"
    --storage "$STORAGE"
    --rootfs "${STORAGE}:${DISK}"
    --memory "$MEMORY"
    --cores "$CORES"
    --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp"
    --features nesting=1
)

if ! $PRIVILEGED; then
    pct_args+=(--unprivileged 1)
fi

"${pct_args[@]}"

# ── Start if requested ─────────────────────────────────────────────
if $START; then
    echo "Starting container..."
    pct start "$CTID"
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "Container created successfully."
echo "  CTID:     $CTID"
echo "  Hostname: $HOSTNAME"
echo "  Tier:     $TIER"
echo "  Layers:   ${layers[*]}"
echo "  Memory:   ${MEMORY} MB"
echo "  Cores:    $CORES"
echo "  Disk:     ${DISK} GB"
echo "  Storage:  $STORAGE"
echo "  Bridge:   $BRIDGE"
if $PRIVILEGED; then
    echo "  Mode:     privileged"
else
    echo "  Mode:     unprivileged"
fi
if $START; then
    echo "  Status:   running"
else
    echo "  Status:   stopped (use 'pct start $CTID' to boot)"
fi
