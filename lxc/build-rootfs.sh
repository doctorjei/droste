#!/usr/bin/env bash
# Build LXC rootfs tarballs for droste tiers.
#
# Usage:
#   lxc/build-rootfs.sh fiber   # Build fiber tier (thread equivalent) on seed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/output"

usage() {
    cat <<EOF
Usage: $(basename "$0") TIER

Build LXC rootfs tarballs for droste tiers.

Tiers:
  fiber      Build fiber tier (thread equivalent) on top of seed
  sheet      Build sheet tier (yarn equivalent) on top of fiber
  page       Build page tier (fabric equivalent) on top of sheet
  tome       Build tome tier (tapestry equivalent) on top of page
  gutenberg  Build gutenberg tier (loom equivalent) on top of tome

Requires droste-seed.tar.xz in output/ (built by build-seed.sh).
Each tier requires the previous tier's tarball in output/.

Output:
  output/droste-fiber.tar.gz      Fiber tier rootfs
  output/droste-sheet.tar.gz      Sheet tier rootfs
  output/droste-page.tar.gz       Page tier rootfs
  output/droste-tome.tar.gz       Tome tier rootfs
  output/droste-gutenberg.tar.gz  Gutenberg tier rootfs
EOF
}

cleanup_mounts() {
    local rootfs="$1"
    mountpoint -q "$rootfs/dev/pts"  2>/dev/null && umount "$rootfs/dev/pts"  || true
    mountpoint -q "$rootfs/dev"      2>/dev/null && umount "$rootfs/dev"      || true
    mountpoint -q "$rootfs/proc"     2>/dev/null && umount "$rootfs/proc"     || true
    mountpoint -q "$rootfs/sys"      2>/dev/null && umount "$rootfs/sys"      || true
}

cleanup() {
    local rootfs="$1"
    if [[ -d "$rootfs" ]]; then
        cleanup_mounts "$rootfs"
        rm -rf "$rootfs"
    fi
}

# ── Fiber: provision thread-equivalent packages on seed ────────────
do_build_fiber() {
    # Ensure seed exists
    if [[ ! -f "$OUTPUT_DIR/droste-seed.tar.xz" ]]; then
        echo "Error: seed rootfs not found at $OUTPUT_DIR/droste-seed.tar.xz" >&2
        echo "Build it first with: lxc/build-seed.sh" >&2
        exit 1
    fi

    # Require root for chroot and bind mounts
    if [[ $EUID -ne 0 ]]; then
        echo "Error: fiber build requires root (for chroot and bind mounts)" >&2
        exit 1
    fi

    local work_dir
    work_dir=$(mktemp -d "/tmp/droste-fiber.XXXXXX")
    trap "cleanup '$work_dir'" EXIT

    echo "Extracting seed rootfs to $work_dir..."
    tar -xf "$OUTPUT_DIR/droste-seed.tar.xz" -C "$work_dir"

    echo "Setting up bind mounts..."
    mount --bind /dev "$work_dir/dev"
    mount --bind /proc "$work_dir/proc"
    mount --bind /sys "$work_dir/sys"
    mount -t devpts devpts "$work_dir/dev/pts"

    # DNS resolution inside chroot (remove symlink if present, e.g. systemd-resolved)
    rm -f "$work_dir/etc/resolv.conf"
    cp /etc/resolv.conf "$work_dir/etc/resolv.conf"

    # Copy files needed by provision script
    cp "$PROJECT_DIR/ansible/files/pystrings" "$work_dir/tmp/pystrings"
    cp "$PROJECT_DIR/ansible/files/pyhttpd" "$work_dir/tmp/pyhttpd"

    # Write provision script (single-quoted heredoc — no variable expansion)
    cat > "$work_dir/tmp/provision.sh" <<'PROVISION'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Strip documentation ──────────────────────────────────────────
cat > /etc/dpkg/dpkg.cfg.d/01-nodoc <<'DPKG_CONF'
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/info/*
path-exclude /usr/share/locale/*
path-include /usr/share/locale/en*
path-include /usr/share/locale/zh*
path-include /usr/share/locale/hi*
path-include /usr/share/locale/es*
path-include /usr/share/locale/ar*
path-include /usr/share/locale/fr*
path-include /usr/share/locale/bn*
path-include /usr/share/locale/pt*
path-include /usr/share/locale/id*
path-include /usr/share/locale/ur*
path-include /usr/share/locale/de*
path-include /usr/share/locale/ja*
path-include /usr/share/locale/ko*
DPKG_CONF

rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
find /usr/share/locale -mindepth 1 -maxdepth 1 \
    ! -name 'en*' ! -name 'zh*' ! -name 'hi*' ! -name 'es*' \
    ! -name 'ar*' ! -name 'fr*' ! -name 'bn*' ! -name 'pt*' \
    ! -name 'id*' ! -name 'ur*' ! -name 'de*' ! -name 'ja*' \
    ! -name 'ko*' -exec rm -rf {} + 2>/dev/null || true

# ── Install packages ────────────────────────────────────────────
# Thread packages minus qemu-guest-agent and watchdog
# (packages already in seed will be skipped by apt)
apt-get update
apt-get install -y --no-install-recommends \
    lxc podman fuse-overlayfs slirp4netns uidmap systemd-container \
    iproute2 dnsmasq nftables ipcalc ipvsadm \
    sudo openssh-server \
    curl jq rsync tmux smbclient git wget make file \
    netcat-openbsd dnsutils tree unzip zip pipx htop patch bc \
    inetutils-telnet ssh-import-id molly-guard debootstrap sshpass xmlstarlet \
    lsof strace sysstat iotop iftop psmisc expect moreutils \
    rename entr jo whois sqlite3 atop etckeeper tftpd-hpa \
    cifs-utils nfs-common sshfs \
    acl attr \
    wireguard-tools \
    conntrack ipset \
    socat fping iputils-arping \
    parallel \
    dnstop fatrace inotify-tools \
    crudini \
    lxcfs \
    ltrace \
    pv \
    bsdextrautils xxd \
    locales

# ── Locales ──────────────────────────────────────────────────────
cat >> /etc/locale.gen <<'LOCALE_LIST'
en_US.UTF-8 UTF-8
zh_CN.UTF-8 UTF-8
zh_TW.UTF-8 UTF-8
hi_IN.UTF-8 UTF-8
es_ES.UTF-8 UTF-8
ar_SA.UTF-8 UTF-8
fr_FR.UTF-8 UTF-8
bn_IN.UTF-8 UTF-8
pt_BR.UTF-8 UTF-8
pt_PT.UTF-8 UTF-8
id_ID.UTF-8 UTF-8
ur_PK.UTF-8 UTF-8
de_DE.UTF-8 UTF-8
ja_JP.UTF-8 UTF-8
ko_KR.UTF-8 UTF-8
LOCALE_LIST
locale-gen

# ── Python micro-tools ──────────────────────────────────────────
install -m 755 /tmp/pystrings /usr/local/bin/pystrings
install -m 755 /tmp/pyhttpd /usr/local/bin/pyhttpd
update-alternatives --install /usr/bin/strings strings /usr/local/bin/pystrings 10
update-alternatives --install /usr/bin/httpd httpd /usr/local/bin/pyhttpd 10
rm -f /tmp/pystrings /tmp/pyhttpd

# ── Droste user ─────────────────────────────────────────────────
existing_user=$(getent passwd 1000 | cut -d: -f1 || true)
if [ -n "$existing_user" ] && [ "$existing_user" != "droste" ]; then
    userdel -r "$existing_user"
fi
existing_group=$(getent group 1000 | cut -d: -f1 || true)
if [ -n "$existing_group" ] && [ "$existing_group" != "droste" ]; then
    groupdel "$existing_group"
fi
groupadd -g 1000 droste 2>/dev/null || true
useradd -u 1000 -g droste -m -s /bin/bash droste 2>/dev/null || true
echo 'droste:droste' | chpasswd
printf 'droste ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/droste
chmod 0440 /etc/sudoers.d/droste

# ── Rootless Podman ──────────────────────────────────────────────
printf 'droste:100000:65536\n' >> /etc/subuid
printf 'droste:100000:65536\n' >> /etc/subgid
mkdir -p /home/droste/.config/containers
cat > /home/droste/.config/containers/storage.conf <<'STORAGE_CONF'
[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
STORAGE_CONF
chown -R droste:droste /home/droste/.config

# ── SSH hardening ────────────────────────────────────────────────
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl enable ssh 2>/dev/null || true

# ── IP forwarding ────────────────────────────────────────────────
cat > /etc/sysctl.d/99-droste.conf <<'SYSCTL_CONF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
SYSCTL_CONF

# ── Clean up ─────────────────────────────────────────────────────
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /tmp/provision.sh
PROVISION

    chmod +x "$work_dir/tmp/provision.sh"

    echo "Running provision script in chroot..."
    chroot "$work_dir" /tmp/provision.sh

    # Unmount bind mounts
    echo "Cleaning up mounts..."
    cleanup_mounts "$work_dir"

    # Create output tarball
    echo "Creating output tarball..."
    mkdir -p "$OUTPUT_DIR"
    tar -czf "$OUTPUT_DIR/droste-fiber.tar.gz" -C "$work_dir" .

    echo ""
    echo "Output: $OUTPUT_DIR/droste-fiber.tar.gz"
    ls -lh "$OUTPUT_DIR/droste-fiber.tar.gz"

    # Clean up work directory
    rm -rf "$work_dir"
    trap - EXIT
}

# ── Sheet: provision yarn-equivalent packages on fiber ───────────────
do_build_sheet() {
    # Ensure fiber exists
    if [[ ! -f "$OUTPUT_DIR/droste-fiber.tar.gz" ]]; then
        echo "Error: fiber rootfs not found at $OUTPUT_DIR/droste-fiber.tar.gz" >&2
        echo "Build it first with: lxc/build-rootfs.sh fiber" >&2
        exit 1
    fi

    # Require root for chroot and bind mounts
    if [[ $EUID -ne 0 ]]; then
        echo "Error: sheet build requires root (for chroot and bind mounts)" >&2
        exit 1
    fi

    local work_dir
    work_dir=$(mktemp -d "/tmp/droste-sheet.XXXXXX")
    trap "cleanup '$work_dir'" EXIT

    echo "Extracting fiber rootfs to $work_dir..."
    tar -xf "$OUTPUT_DIR/droste-fiber.tar.gz" -C "$work_dir"

    echo "Setting up bind mounts..."
    mount --bind /dev "$work_dir/dev"
    mount --bind /proc "$work_dir/proc"
    mount --bind /sys "$work_dir/sys"
    mount -t devpts devpts "$work_dir/dev/pts"

    # DNS resolution inside chroot
    rm -f "$work_dir/etc/resolv.conf"
    cp /etc/resolv.conf "$work_dir/etc/resolv.conf"

    # Write provision script
    cat > "$work_dir/tmp/provision.sh" <<'PROVISION'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Packages before: $(dpkg -l | grep '^ii' | wc -l)"

apt-get update
apt-get install -y --no-install-recommends \
    ansible gettext-base \
    squashfs-tools cloud-image-utils qemu-utils \
    dosfstools mtools ntfs-3g \
    gdisk parted btrfs-progs \
    cryptsetup mdadm \
    ncdu \
    hping3 bmon nethogs nicstat ethtool \
    lshw sysbench picocom \
    lvm2 thin-provisioning-tools nbd-client quota \
    pciutils hdparm dmidecode bridge-utils

echo "Packages after: $(dpkg -l | grep '^ii' | wc -l)"

# ── Clean up ─────────────────────────────────────────────────────
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /tmp/provision.sh
PROVISION

    chmod +x "$work_dir/tmp/provision.sh"

    echo "Running provision script in chroot..."
    chroot "$work_dir" /tmp/provision.sh

    # Unmount bind mounts
    echo "Cleaning up mounts..."
    cleanup_mounts "$work_dir"

    # Create output tarball
    echo "Creating output tarball..."
    mkdir -p "$OUTPUT_DIR"
    tar -czf "$OUTPUT_DIR/droste-sheet.tar.gz" -C "$work_dir" .

    echo ""
    echo "Output: $OUTPUT_DIR/droste-sheet.tar.gz"
    ls -lh "$OUTPUT_DIR/droste-sheet.tar.gz"

    # Clean up work directory
    rm -rf "$work_dir"
    trap - EXIT
}

# ── Page: provision fabric-equivalent packages on sheet ──────────────
do_build_page() {
    # Ensure sheet exists
    if [[ ! -f "$OUTPUT_DIR/droste-sheet.tar.gz" ]]; then
        echo "Error: sheet rootfs not found at $OUTPUT_DIR/droste-sheet.tar.gz" >&2
        echo "Build it first with: lxc/build-rootfs.sh sheet" >&2
        exit 1
    fi

    # Require root for chroot and bind mounts
    if [[ $EUID -ne 0 ]]; then
        echo "Error: page build requires root (for chroot and bind mounts)" >&2
        exit 1
    fi

    local work_dir
    work_dir=$(mktemp -d "/tmp/droste-page.XXXXXX")
    trap "cleanup '$work_dir'" EXIT

    echo "Extracting sheet rootfs to $work_dir..."
    tar -xf "$OUTPUT_DIR/droste-sheet.tar.gz" -C "$work_dir"

    echo "Setting up bind mounts..."
    mount --bind /dev "$work_dir/dev"
    mount --bind /proc "$work_dir/proc"
    mount --bind /sys "$work_dir/sys"
    mount -t devpts devpts "$work_dir/dev/pts"

    # DNS resolution inside chroot
    rm -f "$work_dir/etc/resolv.conf"
    cp /etc/resolv.conf "$work_dir/etc/resolv.conf"

    # Write provision script
    cat > "$work_dir/tmp/provision.sh" <<'PROVISION'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Packages before: $(dpkg -l | grep '^ii' | wc -l)"

apt-get update

# Main batch
apt-get install -y --no-install-recommends \
    clustershell \
    pcs pacemaker pacemaker-cli-utils resource-agents \
    keepalived ebtables fence-agents-common \
    pxelinux syslinux-common \
    drbd-utils sbd dlm-controld \
    open-iscsi targetcli-fb multipath-tools

# Individual (large)
apt-get install -y --no-install-recommends ceph-common

echo "Packages after: $(dpkg -l | grep '^ii' | wc -l)"

# ── Clean up ─────────────────────────────────────────────────────
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /tmp/provision.sh
PROVISION

    chmod +x "$work_dir/tmp/provision.sh"

    echo "Running provision script in chroot..."
    chroot "$work_dir" /tmp/provision.sh

    # Unmount bind mounts
    echo "Cleaning up mounts..."
    cleanup_mounts "$work_dir"

    # Create output tarball
    echo "Creating output tarball..."
    mkdir -p "$OUTPUT_DIR"
    tar -czf "$OUTPUT_DIR/droste-page.tar.gz" -C "$work_dir" .

    echo ""
    echo "Output: $OUTPUT_DIR/droste-page.tar.gz"
    ls -lh "$OUTPUT_DIR/droste-page.tar.gz"

    # Clean up work directory
    rm -rf "$work_dir"
    trap - EXIT
}

# ── Tome: provision tapestry-equivalent packages on page ─────────────
do_build_tome() {
    # Ensure page exists
    if [[ ! -f "$OUTPUT_DIR/droste-page.tar.gz" ]]; then
        echo "Error: page rootfs not found at $OUTPUT_DIR/droste-page.tar.gz" >&2
        echo "Build it first with: lxc/build-rootfs.sh page" >&2
        exit 1
    fi

    # Require root for chroot and bind mounts
    if [[ $EUID -ne 0 ]]; then
        echo "Error: tome build requires root (for chroot and bind mounts)" >&2
        exit 1
    fi

    local work_dir
    work_dir=$(mktemp -d "/tmp/droste-tome.XXXXXX")
    trap "cleanup '$work_dir'" EXIT

    echo "Extracting page rootfs to $work_dir..."
    tar -xf "$OUTPUT_DIR/droste-page.tar.gz" -C "$work_dir"

    echo "Setting up bind mounts..."
    mount --bind /dev "$work_dir/dev"
    mount --bind /proc "$work_dir/proc"
    mount --bind /sys "$work_dir/sys"
    mount -t devpts devpts "$work_dir/dev/pts"

    # DNS resolution inside chroot
    rm -f "$work_dir/etc/resolv.conf"
    cp /etc/resolv.conf "$work_dir/etc/resolv.conf"

    # Write provision script
    cat > "$work_dir/tmp/provision.sh" <<'PROVISION'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Packages before: $(dpkg -l | grep '^ii' | wc -l)"

apt-get update

# Main batch
apt-get install -y --no-install-recommends \
    openvswitch-switch nmap bird2 \
    haproxy apache2-utils \
    fio stress-ng iperf3 \
    buildah skopeo \
    prometheus-node-exporter lnav \
    postgresql-client redis-tools \
    lynis aide \
    arp-scan tcpreplay auditd \
    blktrace xorriso ipmitool \
    sg3-utils smartmontools apparmor-utils

# Individual (large, ~124 MB)
apt-get install -y --no-install-recommends tshark

# Individual (large, ARM emulator)
apt-get install -y --no-install-recommends qemu-system-arm

echo "Packages after: $(dpkg -l | grep '^ii' | wc -l)"

# ── Clean up ─────────────────────────────────────────────────────
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /tmp/provision.sh
PROVISION

    chmod +x "$work_dir/tmp/provision.sh"

    echo "Running provision script in chroot..."
    chroot "$work_dir" /tmp/provision.sh

    # Unmount bind mounts
    echo "Cleaning up mounts..."
    cleanup_mounts "$work_dir"

    # Create output tarball
    echo "Creating output tarball..."
    mkdir -p "$OUTPUT_DIR"
    tar -czf "$OUTPUT_DIR/droste-tome.tar.gz" -C "$work_dir" .

    echo ""
    echo "Output: $OUTPUT_DIR/droste-tome.tar.gz"
    ls -lh "$OUTPUT_DIR/droste-tome.tar.gz"

    # Clean up work directory
    rm -rf "$work_dir"
    trap - EXIT
}

# ── Gutenberg: provision loom-equivalent packages on tome ────────────
do_build_gutenberg() {
    # Ensure tome exists
    if [[ ! -f "$OUTPUT_DIR/droste-tome.tar.gz" ]]; then
        echo "Error: tome rootfs not found at $OUTPUT_DIR/droste-tome.tar.gz" >&2
        echo "Build it first with: lxc/build-rootfs.sh tome" >&2
        exit 1
    fi

    # Require root for chroot and bind mounts
    if [[ $EUID -ne 0 ]]; then
        echo "Error: gutenberg build requires root (for chroot and bind mounts)" >&2
        exit 1
    fi

    local work_dir
    work_dir=$(mktemp -d "/tmp/droste-gutenberg.XXXXXX")
    trap "cleanup '$work_dir'" EXIT

    echo "Extracting tome rootfs to $work_dir..."
    tar -xf "$OUTPUT_DIR/droste-tome.tar.gz" -C "$work_dir"

    echo "Setting up bind mounts..."
    mount --bind /dev "$work_dir/dev"
    mount --bind /proc "$work_dir/proc"
    mount --bind /sys "$work_dir/sys"
    mount -t devpts devpts "$work_dir/dev/pts"

    # DNS resolution inside chroot
    rm -f "$work_dir/etc/resolv.conf"
    cp /etc/resolv.conf "$work_dir/etc/resolv.conf"

    # Write provision script
    cat > "$work_dir/tmp/provision.sh" <<'PROVISION'
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "Packages before: $(dpkg -l | grep '^ii' | wc -l)"

apt-get update
apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config \
    autoconf automake libtool \
    gdb valgrind \
    ccache ninja-build bear

echo "Packages after: $(dpkg -l | grep '^ii' | wc -l)"

# ── Clean up ─────────────────────────────────────────────────────
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /tmp/provision.sh
PROVISION

    chmod +x "$work_dir/tmp/provision.sh"

    echo "Running provision script in chroot..."
    chroot "$work_dir" /tmp/provision.sh

    # Unmount bind mounts
    echo "Cleaning up mounts..."
    cleanup_mounts "$work_dir"

    # Create output tarball
    echo "Creating output tarball..."
    mkdir -p "$OUTPUT_DIR"
    tar -czf "$OUTPUT_DIR/droste-gutenberg.tar.gz" -C "$work_dir" .

    echo ""
    echo "Output: $OUTPUT_DIR/droste-gutenberg.tar.gz"
    ls -lh "$OUTPUT_DIR/droste-gutenberg.tar.gz"

    # Clean up work directory
    rm -rf "$work_dir"
    trap - EXIT
}

# ── Main ─────────────────────────────────────────────────────────────
case "${1:-}" in
    fiber)     do_build_fiber ;;
    sheet)     do_build_sheet ;;
    page)      do_build_page ;;
    tome)      do_build_tome ;;
    gutenberg) do_build_gutenberg ;;
    -h|--help) usage ;;
    *)
        if [[ -z "${1:-}" ]]; then
            usage
        else
            echo "Unknown tier: $1" >&2
            usage >&2
            exit 1
        fi
        ;;
esac
