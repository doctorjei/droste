#!/usr/bin/env bash
# Build the droste-seed OCI base image from a seed tarball.
#
# Extracts seed, chroots in, removes the 21 LXC-specific packages
# (systemd, dbus, udev, cloud-init, etc.), then imports the result
# as an OCI image via podman/docker.
#
# droste-seed is the shared OCI core: everything in the LXC seed that
# works in plain OCI containers. droste-seed-lxc layers on top to add
# init/systemd back for kento (OCI-backed LXC system containers).
#
# Usage:
#   build-seed.sh
#   build-seed.sh --seed /path/to/droste-seed.tar.xz
#   build-seed.sh --no-import    # Build rootfs only, skip container import
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Defaults ────────────────────────────────────────────────────────
SEED_TARBALL="${PROJECT_DIR}/output/droste-seed.tar.xz"
EXCLUDE_LIST="${PROJECT_DIR}/oci/seed-oci-exclude.txt"
DO_IMPORT=true

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build the droste-seed OCI base image from a seed tarball.

Extracts the seed rootfs, removes LXC-specific packages (systemd,
dbus, udev, etc.), and imports the result as an OCI image.

Options:
  -s, --seed PATH      Path to droste-seed.tar.xz (default: output/droste-seed.tar.xz)
  -e, --exclude PATH   Path to exclusion list (default: oci/seed-oci-exclude.txt)
      --no-import      Build rootfs tarball only, skip container import
  -h, --help           Show help

Requires: root (for chroot), podman or docker (for import).
EOF
}

# ── Parse arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--seed)       SEED_TARBALL="$2"; shift 2 ;;
        -e|--exclude)    EXCLUDE_LIST="$2"; shift 2 ;;
        --no-import)     DO_IMPORT=false; shift ;;
        -h|--help)       usage; exit 0 ;;
        -*)              echo "Error: unknown option: $1" >&2; usage >&2; exit 1 ;;
        *)               echo "Error: unexpected argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# ── Prerequisites ───────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Error: must run as root (for chroot)" >&2
    exit 1
fi

if [[ ! -f "$SEED_TARBALL" ]]; then
    echo "Error: seed tarball not found: $SEED_TARBALL" >&2
    exit 1
fi

if [[ ! -f "$EXCLUDE_LIST" ]]; then
    echo "Error: exclusion list not found: $EXCLUDE_LIST" >&2
    exit 1
fi

detect_container_cmd() {
    if command -v podman &>/dev/null; then
        echo podman
    elif command -v docker &>/dev/null; then
        echo docker
    else
        echo "Error: neither podman nor docker found" >&2
        exit 1
    fi
}

if $DO_IMPORT; then
    CONTAINER_CMD=$(detect_container_cmd)
fi

# ── Build exclusion package list ────────────────────────────────────
EXCLUDE_PKGS=$(grep -v '^#' "$EXCLUDE_LIST" | grep -v '^$' | tr '\n' ' ')
echo "Packages to remove: $EXCLUDE_PKGS"

# ── Work directory ──────────────────────────────────────────────────
WORK_DIR=$(mktemp -d "/tmp/droste-seed.XXXXXX")

cleanup() {
    mountpoint -q "$WORK_DIR/rootfs/dev/pts" 2>/dev/null && umount "$WORK_DIR/rootfs/dev/pts" || true
    mountpoint -q "$WORK_DIR/rootfs/dev"     2>/dev/null && umount "$WORK_DIR/rootfs/dev"     || true
    mountpoint -q "$WORK_DIR/rootfs/proc"    2>/dev/null && umount "$WORK_DIR/rootfs/proc"    || true
    mountpoint -q "$WORK_DIR/rootfs/sys"     2>/dev/null && umount "$WORK_DIR/rootfs/sys"     || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# ── Extract seed ────────────────────────────────────────────────────
echo "Extracting seed tarball..."
mkdir -p "$WORK_DIR/rootfs"
tar -xf "$SEED_TARBALL" -C "$WORK_DIR/rootfs"

# ── Set up chroot ───────────────────────────────────────────────────
echo "Setting up chroot..."
mount --bind /dev "$WORK_DIR/rootfs/dev"
mount --bind /proc "$WORK_DIR/rootfs/proc"
mount --bind /sys "$WORK_DIR/rootfs/sys"
mount -t devpts devpts "$WORK_DIR/rootfs/dev/pts"

rm -f "$WORK_DIR/rootfs/etc/resolv.conf"
cp /etc/resolv.conf "$WORK_DIR/rootfs/etc/resolv.conf"

# ── Remove LXC-specific packages in chroot ──────────────────────────
cat > "$WORK_DIR/rootfs/tmp/strip.sh" <<STRIP_EOF
#!/bin/bash
set -euo pipefail

# Prevent services from starting during removal
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

export DEBIAN_FRONTEND=noninteractive

# Remove LXC-specific packages
apt-get remove -y --purge --allow-remove-essential $EXCLUDE_PKGS

# Autoremove orphans
apt-get autoremove -y --purge

# Clean apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Remove policy-rc.d
rm -f /usr/sbin/policy-rc.d
STRIP_EOF
chmod +x "$WORK_DIR/rootfs/tmp/strip.sh"

echo "Removing LXC-specific packages in chroot..."
chroot "$WORK_DIR/rootfs" /tmp/strip.sh
rm -f "$WORK_DIR/rootfs/tmp/strip.sh"

# ── Tear down chroot ───────────────────────────────────────────────
echo "Cleaning up mounts..."
umount "$WORK_DIR/rootfs/dev/pts"
umount "$WORK_DIR/rootfs/dev"
umount "$WORK_DIR/rootfs/proc"
umount "$WORK_DIR/rootfs/sys"

# ── Create rootfs tarball ───────────────────────────────────────────
OUTPUT_TARBALL="${PROJECT_DIR}/output/droste-seed.tar.xz"
echo "Creating rootfs tarball..."
mkdir -p "$PROJECT_DIR/output"
tar -cJf "$OUTPUT_TARBALL" -C "$WORK_DIR/rootfs" .

TARBALL_SIZE=$(du -h "$OUTPUT_TARBALL" | cut -f1)
echo "Output: $OUTPUT_TARBALL ($TARBALL_SIZE)"

# ── Import into container engine ────────────────────────────────────
if $DO_IMPORT; then
    echo "Importing into $CONTAINER_CMD as droste-seed..."
    # podman import chokes on .tar.xz — decompress for import, then clean up
    IMPORT_TARBALL="${WORK_DIR}/droste-seed-import.tar"
    xz -dc "$OUTPUT_TARBALL" > "$IMPORT_TARBALL"
    $CONTAINER_CMD import "$IMPORT_TARBALL" droste-seed
    rm -f "$IMPORT_TARBALL"
    echo ""
    echo "Image imported."
    $CONTAINER_CMD image inspect droste-seed --format '{{.Size}}' | \
        awk '{printf "Image size: %.0f MB\n", $1/1024/1024}'
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "droste-seed built successfully."
echo "  Source:   $SEED_TARBALL"
echo "  Removed:  $(echo $EXCLUDE_PKGS | wc -w) packages"
echo "  Tarball:  $OUTPUT_TARBALL ($TARBALL_SIZE)"
if $DO_IMPORT; then
    echo "  Image:    droste-seed ($CONTAINER_CMD)"
fi
