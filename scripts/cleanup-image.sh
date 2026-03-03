#!/usr/bin/env bash
# Clean up a droste image before final QCOW2 compression.
#
# Extracted from ansible playbook cleanup sections. Runs as root
# inside the packer guest after provisioning and testing.
#
# Usage:
#   sudo /tmp/cleanup-image.sh
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
    echo "Error: must run as root" >&2
    exit 1
fi

# Remove orphaned dependencies
apt-get autoremove -y

# Clean apt cache (all cached .deb files)
apt-get clean

# Remove apt lists
rm -rf /var/lib/apt/lists/*

# Clear machine-id for cloud-init first-boot
: > /etc/machine-id
chmod 0444 /etc/machine-id

# Re-harden SSH (disable password auth after Packer build)
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

# Truncate all logs
find /var/log -type f -exec truncate -s 0 {} +

# Zero free space for QCOW2 compression
dd if=/dev/zero of=/var/tmp/zeros bs=1M 2>/dev/null || true
rm -f /var/tmp/zeros
sync
