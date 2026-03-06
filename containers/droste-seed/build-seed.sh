#!/usr/bin/env bash
# Build the droste-seed OCI base image from the Debian 13 genericcloud image.
#
# Downloads the genericcloud qcow2, extracts the rootfs via qemu-nbd, removes
# kernel/boot packages and init/systemd packages (the 21 OCI exclusions),
# creates the droste user, and imports the result as an OCI image.
#
# droste-seed is the shared OCI core: everything in the genericcloud image that
# works in plain OCI containers. droste-seed-lxc layers on top to add
# init/systemd back for kento (OCI-backed LXC system containers).
#
# Usage:
#   build-seed.sh
#   build-seed.sh --no-import    # Build rootfs only, skip container import
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── Defaults ────────────────────────────────────────────────────────
DOWNLOAD_DIR="$PROJECT_DIR/download"
SEED_TARGET="$SCRIPT_DIR/seed-target.txt"
EXCLUDE_LIST="$PROJECT_DIR/oci/seed-oci-exclude.txt"
DO_IMPORT=true

QCOW2_URL="https://cloud.debian.org/images/cloud/trixie/latest"
QCOW2_FILE="debian-13-genericcloud-amd64.qcow2"
NBD_DEV="/dev/nbd0"

# Packages to purge from the genericcloud rootfs.
# Kernel, bootloader, UEFI, and container-irrelevant packages.
PURGE_PACKAGES=(
    busybox
    cloud-initramfs-growroot
    dracut-install
    grub-cloud-amd64
    grub-common
    grub-efi-amd64-bin
    grub-efi-amd64-signed
    grub-efi-amd64-unsigned
    grub-pc-bin
    grub2-common
    libefiboot1t64
    libefivar1t64
    libfreetype6
    libnetplan1
    libpng16-16t64
    linux-image-cloud-amd64
    linux-sysctl-defaults
    mokutil
    netplan-generator
    netplan.io
    os-prober
    pci.ids
    pciutils
    python3-netplan
    shim-helpers-amd64-signed
    shim-signed
    shim-signed-common
    shim-unsigned
)

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build the droste-seed OCI base image from the Debian 13 genericcloud qcow2.

Downloads the image, extracts the rootfs, removes kernel/boot and init/systemd
packages, creates the droste user, and imports the result as an OCI image.

Options:
      --no-import      Build rootfs only, skip container import
  -h, --help           Show help

Requires: root (for qemu-nbd, mount, chroot), podman or docker (for import).

Downloads are cached in download/ to avoid redundant fetches.
EOF
}

# ── Parse arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-import)     DO_IMPORT=false; shift ;;
        -h|--help)       usage; exit 0 ;;
        -*)              echo "Error: unknown option: $1" >&2; usage >&2; exit 1 ;;
        *)               echo "Error: unexpected argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# ── Prerequisites ───────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "Error: must run as root (for qemu-nbd, mount, chroot)" >&2
    exit 1
fi

if [[ ! -f "$SEED_TARGET" ]]; then
    echo "Error: seed target list not found: $SEED_TARGET" >&2
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

# ── Cleanup helpers ─────────────────────────────────────────────────
cleanup_mounts() {
    local rootfs="$1"
    mountpoint -q "$rootfs/dev/pts"  2>/dev/null && umount "$rootfs/dev/pts"  || true
    mountpoint -q "$rootfs/dev"      2>/dev/null && umount "$rootfs/dev"      || true
    mountpoint -q "$rootfs/proc"     2>/dev/null && umount "$rootfs/proc"     || true
    mountpoint -q "$rootfs/sys"      2>/dev/null && umount "$rootfs/sys"      || true
}

cleanup_nbd() {
    local mnt="$1"
    mountpoint -q "$mnt" 2>/dev/null && umount "$mnt" || true
    qemu-nbd -d "$NBD_DEV" 2>/dev/null || true
}

cleanup() {
    if [[ -d "${WORK_DIR:-}" ]]; then
        cleanup_mounts "$WORK_DIR"
        rm -rf "$WORK_DIR"
    fi
    if [[ -d "${MNT_DIR:-}" ]]; then
        cleanup_nbd "$MNT_DIR"
        rm -rf "$MNT_DIR"
    fi
}
trap cleanup EXIT

# ── Download and verify qcow2 ──────────────────────────────────────
mkdir -p "$DOWNLOAD_DIR"

CACHED="$DOWNLOAD_DIR/$QCOW2_FILE"
if [[ -f "$CACHED" ]]; then
    echo "Using cached download: $CACHED"
else
    echo "Downloading $QCOW2_FILE..."
    curl -L --progress-bar -o "$CACHED.tmp" "$QCOW2_URL/$QCOW2_FILE"
    mv "$CACHED.tmp" "$CACHED"
fi

echo "Verifying SHA512..."
EXPECTED_SHA=$(curl -sL "$QCOW2_URL/SHA512SUMS" \
    | grep "$QCOW2_FILE" | awk '{print $1}')
if [[ -z "$EXPECTED_SHA" ]]; then
    echo "Warning: could not fetch SHA512 checksum, skipping verification" >&2
else
    ACTUAL_SHA=$(sha512sum "$CACHED" | awk '{print $1}')
    if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
        echo "Error: SHA512 mismatch" >&2
        echo "  expected: $EXPECTED_SHA" >&2
        echo "  actual:   $ACTUAL_SHA" >&2
        rm -f "$CACHED"
        exit 1
    fi
    echo "SHA512 verified."
fi

# ── Extract rootfs via qemu-nbd ────────────────────────────────────
MNT_DIR=$(mktemp -d "/tmp/droste-seed-mnt.XXXXXX")
WORK_DIR=$(mktemp -d "/tmp/droste-seed-rootfs.XXXXXX")

modprobe nbd max_part=8

echo "Connecting qcow2 to $NBD_DEV..."
qemu-nbd -c "$NBD_DEV" "$CACHED" --read-only

sleep 2
partprobe "$NBD_DEV" 2>/dev/null || true
sleep 1

# Find root partition — genericcloud uses partition 1 (or 2 if p1 is EFI)
ROOT_PART="${NBD_DEV}p1"
P1_FSTYPE=$(blkid -o value -s TYPE "${NBD_DEV}p1" 2>/dev/null || true)
if [[ "$P1_FSTYPE" == "vfat" ]] && [[ -b "${NBD_DEV}p2" ]]; then
    ROOT_PART="${NBD_DEV}p2"
fi

echo "Mounting root partition ($ROOT_PART) at $MNT_DIR..."
mount -o ro "$ROOT_PART" "$MNT_DIR"

echo "Copying rootfs..."
cp -a "$MNT_DIR/." "$WORK_DIR/"

echo "Disconnecting qcow2..."
cleanup_nbd "$MNT_DIR"

# ── Set up chroot ───────────────────────────────────────────────────
echo "Setting up chroot..."
mount --bind /dev "$WORK_DIR/dev"
mount --bind /proc "$WORK_DIR/proc"
mount --bind /sys "$WORK_DIR/sys"
mount -t devpts devpts "$WORK_DIR/dev/pts"

rm -f "$WORK_DIR/etc/resolv.conf"
cp /etc/resolv.conf "$WORK_DIR/etc/resolv.conf"

# Write package lists into chroot
printf '%s\n' "${PURGE_PACKAGES[@]}" > "$WORK_DIR/tmp/purge-list.txt"
grep -v '^#' "$SEED_TARGET" | grep -v '^$' > "$WORK_DIR/tmp/seed-keep.txt"

# ── Strip packages in chroot ────────────────────────────────────────
# The strip script runs inside the chroot. It removes kernel/boot packages
# (PURGE_PACKAGES) and init/systemd packages (OCI exclusions) in one pass.
# The heredoc is NOT single-quoted so $EXCLUDE_PKGS gets expanded.
cat > "$WORK_DIR/tmp/strip.sh" <<STRIP_EOF
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Packages before strip: \$(dpkg -l | grep '^ii' | wc -l)"

# Prevent services from starting during removal
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

# Mark all seed target packages as manually installed so autoremove
# won't pull them out when their reverse-deps get purged
echo "Marking seed packages as manually installed..."
xargs apt-mark manual < /tmp/seed-keep.txt 2>/dev/null || true

# Disable grub postrm hook — grub-probe fails in chroot (no root device)
dpkg-divert --local --rename --add /etc/kernel/postrm.d/zz-update-grub 2>/dev/null || true
rm -f /etc/kernel/postrm.d/zz-update-grub

# Filter purge list to only installed packages (avoids "not installed" noise)
echo "Filtering purge list to installed packages..."
while read -r pkg; do
    if dpkg -s "\$pkg" &>/dev/null; then
        echo "\$pkg"
    fi
done < /tmp/purge-list.txt > /tmp/purge-installed.txt

# Remove dirs that cause "not empty" warnings during purge
rm -rf /etc/grub.d /etc/default/grub.d /etc/kernel/postrm.d

# Phase 1: purge kernel/boot packages
echo "Purging kernel/boot packages..."
if [[ -s /tmp/purge-installed.txt ]]; then
    xargs apt-get purge -y --allow-remove-essential < /tmp/purge-installed.txt 2>&1 \
        | grep -v 'dpkg: warning: this is a protected package'
fi
apt-get autoremove -y || true

# Phase 2: purge init/systemd packages (OCI exclusions)
echo "Purging init/systemd packages..."
apt-get remove -y --purge --allow-remove-essential $EXCLUDE_PKGS
apt-get autoremove -y --purge

# Re-install packages that were collateral damage from autoremove
# (openssh-server depends on libpam-systemd which was in the exclude list)
apt-get update
apt-get install -y --no-install-recommends openssh-server openssh-sftp-server

# Clean apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

# Remove policy-rc.d
rm -f /usr/sbin/policy-rc.d

echo "Packages after strip: \$(dpkg -l | grep '^ii' | wc -l)"
rm -f /tmp/strip.sh /tmp/purge-list.txt /tmp/seed-keep.txt /tmp/purge-installed.txt
STRIP_EOF
chmod +x "$WORK_DIR/tmp/strip.sh"

echo "Running package strip in chroot..."
chroot "$WORK_DIR" /tmp/strip.sh

# ── Set up droste user and base config in chroot ──────────────────
cat > "$WORK_DIR/tmp/setup.sh" <<'SETUP_EOF'
#!/bin/bash
set -euo pipefail

# Droste user (matches VM provisioning)
if ! id droste &>/dev/null; then
    groupadd -g 1000 droste
    useradd -u 1000 -g droste -m -s /bin/bash droste
    printf 'droste ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/droste
    chmod 0440 /etc/sudoers.d/droste
fi

# Sysctl config (written only — shared kernel in containers)
printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' \
    > /etc/sysctl.d/99-droste.conf

# Locales
sed -i '/^# .*UTF-8/{
    /en_US\|zh_CN\|zh_TW\|hi_IN\|es_ES\|ar_SA\|fr_FR\|bn_IN\|pt_BR\|pt_PT\|id_ID\|ur_PK\|de_DE\|ja_JP\|ko_KR/s/^# //
}' /etc/locale.gen
locale-gen
SETUP_EOF
chmod +x "$WORK_DIR/tmp/setup.sh"

echo "Setting up droste user and base config..."
chroot "$WORK_DIR" /tmp/setup.sh
rm -f "$WORK_DIR/tmp/setup.sh"

# ── Tear down chroot ───────────────────────────────────────────────
echo "Cleaning up mounts..."
cleanup_mounts "$WORK_DIR"

# Remove boot artifacts that remain after package purge
rm -rf "$WORK_DIR/boot/"*
rm -rf "$WORK_DIR/lib/modules/"*

# Clear stale fstab from genericcloud (UUID-based mounts for partitions that
# don't exist in containers, and cause boot failures in -vm images)
printf '# Empty — no block devices in OCI base\n' > "$WORK_DIR/etc/fstab"

# ── Import into container engine ────────────────────────────────────
if $DO_IMPORT; then
    echo "Importing into $CONTAINER_CMD as droste-seed..."
    tar -c -C "$WORK_DIR" . | $CONTAINER_CMD import - droste-seed
    echo ""
    echo "Image imported."
    $CONTAINER_CMD image inspect droste-seed --format '{{.Size}}' | \
        awk '{printf "Image size: %.0f MB\n", $1/1024/1024}'
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "droste-seed built successfully."
echo "  Source:   $QCOW2_FILE (genericcloud)"
echo "  Removed:  ${#PURGE_PACKAGES[@]} kernel/boot + $(echo $EXCLUDE_PKGS | wc -w) init/systemd packages"
if $DO_IMPORT; then
    echo "  Image:    droste-seed ($CONTAINER_CMD)"
fi
