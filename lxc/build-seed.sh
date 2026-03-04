#!/usr/bin/env bash
# Build the droste-seed LXC rootfs tarball.
#
# Starts from the Debian 13 genericcloud qcow2 image, extracts the rootfs,
# removes kernel/boot/container-irrelevant packages, and produces a minimal
# rootfs tarball suitable as a base for LXC tiers.
#
# Usage:
#   lxc/build-seed.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOWNLOAD_DIR="$PROJECT_DIR/download"
OUTPUT_DIR="$PROJECT_DIR/output"

QCOW2_URL="https://cloud.debian.org/images/cloud/trixie/latest"
QCOW2_FILE="debian-13-genericcloud-amd64.qcow2"
NBD_DEV="/dev/nbd0"

usage() {
    cat <<EOF
Usage: $(basename "$0")

Build the droste-seed LXC rootfs tarball from the Debian 13 genericcloud
qcow2 image. Extracts the rootfs, removes kernel/boot/container-irrelevant
packages, and produces a minimal rootfs tarball.

Requires root (for qemu-nbd, mount, chroot).

Output:
  output/droste-seed.tar.xz

Downloads are cached in download/ to avoid redundant fetches.
EOF
}

# Packages to purge from the genericcloud rootfs.
# Kernel, bootloader, UEFI, and container-irrelevant packages.
# Some additional packages (e.g. linux-image-6.12.73+deb13-cloud-amd64,
# grub-efi, grub-efi-amd64) will be pulled out as dependencies.
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
    local work_dir="$1"
    local mnt="$2"

    if [[ -d "$work_dir" ]]; then
        cleanup_mounts "$work_dir"
        rm -rf "$work_dir"
    fi

    if [[ -d "$mnt" ]]; then
        cleanup_nbd "$mnt"
        rm -rf "$mnt"
    fi
}

# ── Download and verify qcow2 ────────────────────────────────────────
download_qcow2() {
    mkdir -p "$DOWNLOAD_DIR"

    local cached="$DOWNLOAD_DIR/$QCOW2_FILE"

    if [[ -f "$cached" ]]; then
        echo "Using cached download: $cached"
    else
        echo "Downloading $QCOW2_FILE..."
        curl -L --progress-bar -o "$cached.tmp" "$QCOW2_URL/$QCOW2_FILE"
        mv "$cached.tmp" "$cached"
    fi

    # Verify SHA512
    echo "Verifying SHA512..."
    local expected_sha
    expected_sha=$(curl -sL "$QCOW2_URL/SHA512SUMS" \
        | grep "$QCOW2_FILE" | awk '{print $1}')

    if [[ -z "$expected_sha" ]]; then
        echo "Warning: could not fetch SHA512 checksum, skipping verification" >&2
    else
        local actual_sha
        actual_sha=$(sha512sum "$cached" | awk '{print $1}')
        if [[ "$expected_sha" != "$actual_sha" ]]; then
            echo "Error: SHA512 mismatch" >&2
            echo "  expected: $expected_sha" >&2
            echo "  actual:   $actual_sha" >&2
            rm -f "$cached"
            exit 1
        fi
        echo "SHA512 verified."
    fi
}

# ── Main build ────────────────────────────────────────────────────────
do_build() {
    # Require root
    if [[ $EUID -ne 0 ]]; then
        echo "Error: this script requires root (for qemu-nbd, mount, chroot)" >&2
        exit 1
    fi

    download_qcow2

    local mnt
    mnt=$(mktemp -d "/tmp/droste-seed-mnt.XXXXXX")
    local work_dir
    work_dir=$(mktemp -d "/tmp/droste-seed-rootfs.XXXXXX")
    trap "cleanup '$work_dir' '$mnt'" EXIT

    # Load nbd module
    modprobe nbd max_part=8

    # Connect qcow2 to nbd device
    echo "Connecting qcow2 to $NBD_DEV..."
    qemu-nbd -c "$NBD_DEV" "$DOWNLOAD_DIR/$QCOW2_FILE" --read-only

    # Wait for device nodes to appear
    sleep 2
    partprobe "$NBD_DEV" 2>/dev/null || true
    sleep 1

    # Find the root partition — genericcloud uses partition 1
    local root_part=""
    if [[ -b "${NBD_DEV}p1" ]]; then
        root_part="${NBD_DEV}p1"
    elif [[ -b "${NBD_DEV}p2" ]]; then
        root_part="${NBD_DEV}p2"
    else
        echo "Error: no partitions found on $NBD_DEV" >&2
        fdisk -l "$NBD_DEV" >&2
        exit 1
    fi

    # Check if p1 is EFI (vfat) — if so, root is p2
    local p1_fstype
    p1_fstype=$(blkid -o value -s TYPE "${NBD_DEV}p1" 2>/dev/null || true)
    if [[ "$p1_fstype" == "vfat" ]] && [[ -b "${NBD_DEV}p2" ]]; then
        root_part="${NBD_DEV}p2"
    fi

    echo "Mounting root partition ($root_part) at $mnt..."
    mount -o ro "$root_part" "$mnt"

    # Copy rootfs to work directory
    echo "Copying rootfs to $work_dir..."
    cp -a "$mnt/." "$work_dir/"

    # Unmount and disconnect nbd — we have the rootfs now
    echo "Disconnecting qcow2..."
    cleanup_nbd "$mnt"

    # Set up bind mounts for chroot
    echo "Setting up bind mounts..."
    mount --bind /dev "$work_dir/dev"
    mount --bind /proc "$work_dir/proc"
    mount --bind /sys "$work_dir/sys"
    mount -t devpts devpts "$work_dir/dev/pts"

    # DNS resolution inside chroot (remove symlink if present, e.g. systemd-resolved)
    rm -f "$work_dir/etc/resolv.conf"
    cp /etc/resolv.conf "$work_dir/etc/resolv.conf"

    # Write purge list and seed target list into the chroot
    printf '%s\n' "${PURGE_PACKAGES[@]}" > "$work_dir/tmp/purge-list.txt"
    grep -v '^#' "$SCRIPT_DIR/seed-target.txt" | grep -v '^$' > "$work_dir/tmp/seed-keep.txt"

    # Write chroot script (single-quoted heredoc — no escaping needed)
    cat > "$work_dir/tmp/seed-strip.sh" <<'STRIP'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Packages before purge: $(dpkg -l | grep '^ii' | wc -l)"

# Mark all seed target packages as manually installed so autoremove
# won't pull them out when their reverse-deps get purged
echo "Marking seed packages as manually installed..."
xargs apt-mark manual < /tmp/seed-keep.txt 2>/dev/null || true

# Disable grub postrm hook — grub-probe fails in chroot (no root device)
dpkg-divert --local --rename --add /etc/kernel/postrm.d/zz-update-grub 2>/dev/null || true
rm -f /etc/kernel/postrm.d/zz-update-grub

echo "Purging kernel/boot/container-irrelevant packages..."
xargs apt-get purge -y --allow-remove-essential < /tmp/purge-list.txt || true

echo "Running autoremove..."
apt-get autoremove -y || true

echo "Cleaning apt cache..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Packages after purge: $(dpkg -l | grep '^ii' | wc -l)"

rm -f /tmp/seed-strip.sh /tmp/purge-list.txt /tmp/seed-keep.txt
STRIP

    chmod +x "$work_dir/tmp/seed-strip.sh"

    echo "Running package removal in chroot..."
    chroot "$work_dir" /tmp/seed-strip.sh

    # Unmount bind mounts
    echo "Cleaning up mounts..."
    cleanup_mounts "$work_dir"

    # Remove boot artifacts that remain after package purge
    rm -rf "$work_dir/boot/"*
    rm -rf "$work_dir/lib/modules/"*

    # Create output tarball
    mkdir -p "$OUTPUT_DIR"
    echo "Creating output tarball..."
    tar -cJf "$OUTPUT_DIR/droste-seed.tar.xz" -C "$work_dir" .

    echo ""
    echo "Output: $OUTPUT_DIR/droste-seed.tar.xz"
    ls -lh "$OUTPUT_DIR/droste-seed.tar.xz"

    # Clean up
    rm -rf "$work_dir"
    rm -rf "$mnt"
    trap - EXIT
}

# ── Main ──────────────────────────────────────────────────────────────
case "${1:-}" in
    -h|--help) usage ;;
    "")        do_build ;;
    *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
esac
