#!/usr/bin/env bash
# Test ZFS size impact on droste-jacquard without a full rebuild.
#
# Copies the jacquard image, boots it, installs zfsutils-linux,
# shuts down, recompresses, and compares sizes.
#
# Usage:
#   scripts/test-zfs-size.sh --ssh-key ~/.ssh/id_ed25519.pub
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE="$PROJECT_DIR/output-droste-jacquard/droste-jacquard.qcow2"
WORK_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/droste-zfs-test"
COPY="$WORK_DIR/droste-jacquard-zfs.qcow2"
SSH_PORT=2223
SSH_KEY=""

# ── Parse arguments ──────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-key)  SSH_KEY="$2"; shift 2 ;;
        --ssh-port) SSH_PORT="$2"; shift 2 ;;
        *)          echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$SSH_KEY" ]]; then
    for candidate in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
        if [[ -f "$candidate" ]]; then
            SSH_KEY="$candidate"
            break
        fi
    done
    if [[ -z "$SSH_KEY" ]]; then
        echo "Error: no SSH public key found. Use --ssh-key FILE." >&2
        exit 1
    fi
fi

PRIVATE_KEY="${SSH_KEY%.pub}"

if [[ ! -f "$SOURCE" ]]; then
    echo "Error: $SOURCE not found. Build jacquard first." >&2
    exit 1
fi

# ── Copy image ───────────────────────────────────────────────────────
mkdir -p "$WORK_DIR"
echo "Copying jacquard image..."
cp "$SOURCE" "$COPY"
echo "  Source: $(ls -lh "$SOURCE" | awk '{print $5}')"
echo ""

# ── Boot ─────────────────────────────────────────────────────────────
echo "Booting copy on port $SSH_PORT..."
"$SCRIPT_DIR/boot-droste.sh" \
    --ssh-key "$SSH_KEY" \
    --ssh-port "$SSH_PORT" \
    --image "$COPY" \
    --daemonize

echo "Waiting for SSH..."
retries=30
while ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o LogLevel=ERROR -o ConnectTimeout=2 \
          -p "$SSH_PORT" -i "$PRIVATE_KEY" droste@localhost true &>/dev/null; do
    ((retries--))
    if [[ $retries -le 0 ]]; then
        echo "Error: SSH did not become available" >&2
        exit 1
    fi
    sleep 2
done
echo "SSH is up."
echo ""

# ── Install ZFS ──────────────────────────────────────────────────────
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p "$SSH_PORT" -i "$PRIVATE_KEY")

echo "Disabling PVE enterprise repo (requires subscription)..."
ssh "${SSH_OPTS[@]}" droste@localhost "sudo rm -f /etc/apt/sources.list.d/pve-enterprise.list"

echo "Installing zfsutils-linux..."
ssh "${SSH_OPTS[@]}" droste@localhost "sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends zfsutils-linux 2>&1 | tail -5"
echo ""

echo "Checking ZFS:"
ssh "${SSH_OPTS[@]}" droste@localhost "command -v zpool || test -x /usr/sbin/zpool && echo '  + zpool found'" || echo "  - zpool not found"
ssh "${SSH_OPTS[@]}" droste@localhost "command -v zfs || test -x /usr/sbin/zfs && echo '  + zfs found'" || echo "  - zfs not found"
echo ""

# ── Cleanup inside guest ─────────────────────────────────────────────
echo "Cleaning up guest..."
ssh "${SSH_OPTS[@]}" droste@localhost "sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/*"
echo ""

# ── Shutdown ─────────────────────────────────────────────────────────
echo "Shutting down..."
ssh "${SSH_OPTS[@]}" droste@localhost "sudo shutdown -P now" 2>/dev/null || true
sleep 5

# Kill QEMU if still running
PIDFILE="${WORK_DIR}/droste.pid"
if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
fi

# ── Recompress ────────────────────────────────────────────────────────
echo "Recompressing..."
qemu-img convert -O qcow2 -c "$COPY" "$WORK_DIR/droste-jacquard-zfs-compressed.qcow2"
mv "$WORK_DIR/droste-jacquard-zfs-compressed.qcow2" "$COPY"
echo ""

# ── Compare ──────────────────────────────────────────────────────────
echo "=== Size comparison ==="
echo "  Without ZFS: $(ls -lh "$SOURCE" | awk '{print $5}')"
echo "  With ZFS:    $(ls -lh "$COPY" | awk '{print $5}')"
echo ""
echo "Image with ZFS saved to: $COPY"
