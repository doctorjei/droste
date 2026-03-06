#!/usr/bin/env bash
# Deploy a droste VM image to Proxmox VE.
#
# Imports a droste qcow2 image (standalone or diff-chain) into a PVE VM.
# Run this on the Proxmox host, not the build VM.
#
# Usage:
#   droste-pve-vm.sh thread
#   droste-pve-vm.sh --diff --image-dir /mnt/images yarn
#   droste-pve-vm.sh --storage local-lvm --memory 4096 --start jacquard
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Tier chain ──────────────────────────────────────────────────────
ALL_TIERS=(thread yarn fabric tapestry loom jacquard)

tier_index() {
    local target="$1"
    local i=0
    for t in "${ALL_TIERS[@]}"; do
        [[ "$t" == "$target" ]] && echo "$i" && return
        i=$((i + 1))
    done
    return 1
}

# ── Defaults ────────────────────────────────────────────────────────
IMAGE_DIR="."
STORAGE="local"
VMID=""
MEMORY=2048
CORES=2
BRIDGE="vmbr0"
VM_NAME=""
DIFF_MODE=false
START=false
TIER=""

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <tier>

Deploy a droste VM image to Proxmox VE.

Tiers: thread, yarn, fabric, tapestry, loom, jacquard

Options:
  -d, --image-dir DIR    Directory with qcow2 images (default: .)
  -s, --storage POOL     PVE storage pool (default: local)
  -v, --vmid ID          VM ID (default: next available)
  -m, --memory MB        RAM in MB (default: 2048)
  -c, --cores N          CPU cores (default: 2)
  -b, --bridge NAME      Network bridge (default: vmbr0)
  -n, --name NAME        VM name (default: droste-<tier>)
      --diff             Use diff chain instead of standalone
      --start            Start VM after creation
  -h, --help             Show help

Standalone mode (default):
  Imports droste-<tier>.qcow2 directly.

Diff mode (--diff):
  Assembles from droste-thread.qcow2 (base) plus diff images
  (droste-yarn-diff.qcow2, etc.) up to the target tier.
  Rebases and flattens to a temporary image for import.

Examples:
  $(basename "$0") thread
  $(basename "$0") --diff --image-dir /mnt/images yarn
  $(basename "$0") --storage local-lvm --memory 4096 --start jacquard
EOF
}

# ── Parse arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--image-dir) IMAGE_DIR="$2"; shift 2 ;;
        -s|--storage)   STORAGE="$2"; shift 2 ;;
        -v|--vmid)      VMID="$2"; shift 2 ;;
        -m|--memory)    MEMORY="$2"; shift 2 ;;
        -c|--cores)     CORES="$2"; shift 2 ;;
        -b|--bridge)    BRIDGE="$2"; shift 2 ;;
        -n|--name)      VM_NAME="$2"; shift 2 ;;
        --diff)         DIFF_MODE=true; shift ;;
        --start)        START=true; shift ;;
        -h|--help)      usage; exit 0 ;;
        -*)             echo "Error: unknown option: $1" >&2; usage >&2; exit 1 ;;
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
if ! tier_index "$TIER" >/dev/null 2>&1; then
    echo "Error: unknown tier: $TIER" >&2
    echo "Valid tiers: ${ALL_TIERS[*]}" >&2
    exit 1
fi

VM_NAME="${VM_NAME:-droste-${TIER}}"
IMAGE_DIR="$(realpath "$IMAGE_DIR")"

# ── Prerequisites ───────────────────────────────────────────────────
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: must run as root on the Proxmox host" >&2
    exit 1
fi

for cmd in qm qemu-img pvesh; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd not found. Is this a Proxmox host?" >&2
        exit 1
    fi
done

# ── Validate image files ───────────────────────────────────────────
if $DIFF_MODE; then
    # Need base + diffs up to target
    base="${IMAGE_DIR}/droste-thread.qcow2"
    if [[ ! -f "$base" ]]; then
        echo "Error: base image not found: $base" >&2
        exit 1
    fi
    idx=$(tier_index "$TIER")
    for i in $(seq 1 "$idx"); do
        diff="${IMAGE_DIR}/droste-${ALL_TIERS[$i]}-diff.qcow2"
        if [[ ! -f "$diff" ]]; then
            echo "Error: diff image not found: $diff" >&2
            exit 1
        fi
    done
else
    standalone="${IMAGE_DIR}/droste-${TIER}.qcow2"
    if [[ ! -f "$standalone" ]]; then
        echo "Error: image not found: $standalone" >&2
        exit 1
    fi
fi

# ── Auto-assign VMID ───────────────────────────────────────────────
if [[ -z "$VMID" ]]; then
    VMID=$(pvesh get /cluster/nextid)
    echo "Auto-assigned VMID: $VMID"
fi

# ── Cleanup trap ────────────────────────────────────────────────────
TMPDIR=""
cleanup() {
    if [[ -n "$TMPDIR" && -d "$TMPDIR" ]]; then
        rm -rf "$TMPDIR"
    fi
}
trap cleanup EXIT

# ── Prepare import image ───────────────────────────────────────────
IMPORT_IMAGE=""

if $DIFF_MODE; then
    echo "Assembling diff chain for ${TIER}..."
    TMPDIR=$(mktemp -d "/tmp/droste-pve-vm.XXXXXX")
    idx=$(tier_index "$TIER")

    # Copy base
    cp "${IMAGE_DIR}/droste-thread.qcow2" "${TMPDIR}/droste-thread.qcow2"

    # Copy and rebase each diff layer
    prev="droste-thread.qcow2"
    for i in $(seq 1 "$idx"); do
        t="${ALL_TIERS[$i]}"
        diff_name="droste-${t}-diff.qcow2"
        cp "${IMAGE_DIR}/${diff_name}" "${TMPDIR}/${diff_name}"
        qemu-img rebase -u -b "${TMPDIR}/${prev}" -F qcow2 "${TMPDIR}/${diff_name}"
        prev="$diff_name"
    done

    # Flatten to single image
    echo "Flattening to standalone image..."
    flat="${TMPDIR}/droste-${TIER}-flat.qcow2"
    qemu-img convert -O qcow2 -c "${TMPDIR}/${prev}" "$flat"
    IMPORT_IMAGE="$flat"
    echo "Flattened image: $(du -h "$flat" | cut -f1)"
else
    IMPORT_IMAGE="${IMAGE_DIR}/droste-${TIER}.qcow2"
fi

# ── Create VM ──────────────────────────────────────────────────────
echo ""
echo "Creating VM ${VMID} (${VM_NAME})..."

qm create "$VMID" \
    --name "$VM_NAME" \
    --memory "$MEMORY" \
    --cores "$CORES" \
    --cpu cputype=host \
    --ostype l26 \
    --net0 "virtio,bridge=${BRIDGE}" \
    --serial0 socket \
    --vga serial0 \
    --agent enabled=1

echo "Importing disk..."
qm set "$VMID" --scsi0 "${STORAGE}:0,import-from=${IMPORT_IMAGE}"
qm set "$VMID" --scsihw virtio-scsi-single --boot order=scsi0

# ── Start if requested ─────────────────────────────────────────────
if $START; then
    echo "Starting VM..."
    qm start "$VMID"
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "VM created successfully."
echo "  VMID:    $VMID"
echo "  Name:    $VM_NAME"
echo "  Tier:    $TIER"
echo "  Memory:  ${MEMORY} MB"
echo "  Cores:   $CORES"
echo "  Storage: $STORAGE"
echo "  Bridge:  $BRIDGE"
if $DIFF_MODE; then
    echo "  Mode:    diff chain (flattened)"
else
    echo "  Mode:    standalone"
fi
if $START; then
    echo "  Status:  running"
else
    echo "  Status:  stopped (use 'qm start $VMID' to boot)"
fi
