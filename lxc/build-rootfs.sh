#!/usr/bin/env bash
# Build LXC rootfs tarballs for droste tiers.
#
# Usage:
#   lxc/build-rootfs.sh pre-hair    # Download and cache base rootfs
#   lxc/build-rootfs.sh hair        # Build hair tier (thread equivalent)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOWNLOAD_DIR="$PROJECT_DIR/download"
OUTPUT_DIR="$PROJECT_DIR/output"

BASE_URL="https://images.linuxcontainers.org/images/debian/trixie/amd64/cloud"

usage() {
    cat <<EOF
Usage: $(basename "$0") TIER

Build LXC rootfs tarballs for droste tiers.

Tiers:
  pre-hair   Download and verify base Debian rootfs from linuxcontainers.org
  hair       Build hair tier (thread equivalent) on top of pre-hair

Output:
  output/droste-pre-hair.tar.xz   Base rootfs (direct from upstream)
  output/droste-hair.tar.gz       Hair tier rootfs

Downloads are cached in download/ to avoid redundant fetches.
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

# ── Pre-hair: download and verify upstream rootfs ─────────────────────
do_build_pre_hair() {
    mkdir -p "$DOWNLOAD_DIR" "$OUTPUT_DIR"

    echo "Fetching latest build date from images.linuxcontainers.org..."
    local latest_date
    latest_date=$(curl -sL "${BASE_URL}/" \
        | grep -oE '[0-9]{8}_[0-9]{2}:[0-9]{2}' | sort -r | head -1)

    if [[ -z "$latest_date" ]]; then
        echo "Error: could not determine latest build date" >&2
        exit 1
    fi
    echo "Latest build: $latest_date"

    local rootfs_url="${BASE_URL}/${latest_date}/rootfs.tar.xz"
    local sha256_url="${BASE_URL}/${latest_date}/SHA256SUMS"
    local cached="$DOWNLOAD_DIR/rootfs-${latest_date}.tar.xz"

    # Download if not cached
    if [[ -f "$cached" ]]; then
        echo "Using cached download: $cached"
    else
        echo "Downloading rootfs.tar.xz (~116 MB)..."
        curl -L --progress-bar -o "$cached.tmp" "$rootfs_url"
        mv "$cached.tmp" "$cached"
    fi

    # Verify SHA256
    echo "Verifying SHA256..."
    local expected_sha
    expected_sha=$(curl -sL "$sha256_url" | grep 'rootfs.tar.xz' | awk '{print $1}')

    if [[ -z "$expected_sha" ]]; then
        echo "Warning: could not fetch SHA256 checksum, skipping verification" >&2
    else
        local actual_sha
        actual_sha=$(sha256sum "$cached" | awk '{print $1}')
        if [[ "$expected_sha" != "$actual_sha" ]]; then
            echo "Error: SHA256 mismatch" >&2
            echo "  expected: $expected_sha" >&2
            echo "  actual:   $actual_sha" >&2
            rm -f "$cached"
            exit 1
        fi
        echo "SHA256 verified."
    fi

    # Copy to output
    cp "$cached" "$OUTPUT_DIR/droste-pre-hair.tar.xz"
    echo ""
    echo "Output: $OUTPUT_DIR/droste-pre-hair.tar.xz"
    ls -lh "$OUTPUT_DIR/droste-pre-hair.tar.xz"
}

# ── Hair: provision thread-equivalent packages on pre-hair ────────────
do_build_hair() {
    # Ensure pre-hair exists
    if [[ ! -f "$OUTPUT_DIR/droste-pre-hair.tar.xz" ]]; then
        echo "Pre-hair rootfs not found, building first..."
        do_build_pre_hair
        echo ""
    fi

    # Require root for chroot and bind mounts
    if [[ $EUID -ne 0 ]]; then
        echo "Error: hair build requires root (for chroot and bind mounts)" >&2
        exit 1
    fi

    local work_dir
    work_dir=$(mktemp -d "/tmp/droste-hair.XXXXXX")
    trap "cleanup '$work_dir'" EXIT

    echo "Extracting pre-hair rootfs to $work_dir..."
    tar -xf "$OUTPUT_DIR/droste-pre-hair.tar.xz" -C "$work_dir"

    echo "Setting up bind mounts..."
    mount --bind /dev "$work_dir/dev"
    mount --bind /proc "$work_dir/proc"
    mount --bind /sys "$work_dir/sys"
    mount -t devpts devpts "$work_dir/dev/pts"

    # DNS resolution inside chroot
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
    tar -czf "$OUTPUT_DIR/droste-hair.tar.gz" -C "$work_dir" .

    echo ""
    echo "Output: $OUTPUT_DIR/droste-hair.tar.gz"
    ls -lh "$OUTPUT_DIR/droste-hair.tar.gz"

    # Clean up work directory
    rm -rf "$work_dir"
    trap - EXIT
}

# ── Main ─────────────────────────────────────────────────────────────
case "${1:-}" in
    pre-hair)  do_build_pre_hair ;;
    hair)      do_build_hair ;;
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
