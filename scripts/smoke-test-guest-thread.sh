#!/usr/bin/env bash
# Smoke test for droste-thread — runs inside the guest.
#
# Verifies that all expected tools, users, and configuration are present.
# Used by Packer during builds and can also be copied in manually.
#
# Usage:
#   sudo ./smoke-test-guest.sh
set -euo pipefail

# ── Test framework ──────────────────────────────────────────────────
PASS=0
FAIL=0
ERRORS=()

check() {
    local description="$1"
    shift
    if eval "$@" &>/dev/null; then
        echo "  + $description"
        PASS=$((PASS + 1))
    else
        echo "  - FAIL: $description"
        ERRORS+=("$description")
        FAIL=$((FAIL + 1))
    fi
}

echo "droste-thread smoke test (guest)"
echo "==============================="
echo ""

# ── User and permissions ────────────────────────────────────────────
echo "User:"
check "agent user exists"           "id agent"
check "agent UID is 1000"           "test \$(id -u agent) -eq 1000"
check "agent group"                 "id -gn agent | grep -q agent"
check "sudoers entry exists"        "test -f /etc/sudoers.d/agent"
echo ""

# ── Container tools ─────────────────────────────────────────────────
echo "Containers:"
check "lxc-create available"        "command -v lxc-create"
check "podman available"            "command -v podman"
check "fuse-overlayfs available"    "command -v fuse-overlayfs"
check "slirp4netns available"       "command -v slirp4netns"
check "systemd-nspawn available"    "command -v systemd-nspawn"
check "machinectl available"        "command -v machinectl"
echo ""

# ── Networking ──────────────────────────────────────────────────────
echo "Networking:"
check "ip command available"        "command -v ip"
check "dnsmasq available"           "test -x /usr/sbin/dnsmasq"
check "nft available"               "command -v nft"
check "ipcalc available"            "command -v ipcalc"
check "ipvsadm available"           "test -x /usr/sbin/ipvsadm"
check "IPv4 forwarding sysctl"      "grep -q '^net.ipv4.ip_forward = 1' /etc/sysctl.d/99-droste.conf"
check "IPv6 forwarding sysctl"      "grep -q '^net.ipv6.conf.all.forwarding = 1' /etc/sysctl.d/99-droste.conf"
echo ""

# ── Utilities ───────────────────────────────────────────────────────
echo "Utilities:"
check "curl available"              "command -v curl"
check "jq available"                "command -v jq"
check "rsync available"             "command -v rsync"
check "tmux available"              "command -v tmux"
check "smbclient available"         "command -v smbclient"
check "git available"               "command -v git"
check "wget available"              "command -v wget"
check "make available"              "command -v make"
check "file available"              "command -v file"
check "nc available"                "command -v nc"
check "dig available"               "command -v dig"
check "tree available"              "command -v tree"
check "unzip available"             "command -v unzip"
check "zip available"               "command -v zip"
check "pipx available"              "command -v pipx"
check "htop available"              "command -v htop"
check "patch available"             "command -v patch"
check "bc available"                "command -v bc"
check "telnet available"            "command -v telnet"
check "ssh-import-id available"     "command -v ssh-import-id"
check "molly-guard available"       "test -x /usr/sbin/molly-guard || test -x /usr/lib/molly-guard/molly-guard"
check "debootstrap available"       "command -v debootstrap"
check "sshpass available"           "command -v sshpass"
check "xmlstarlet available"        "command -v xmlstarlet"
check "lsof available"              "command -v lsof"
check "strace available"            "command -v strace"
check "sar available"               "command -v sar"
check "iotop available"             "test -x /usr/sbin/iotop"
check "iftop available"             "test -x /usr/sbin/iftop"
check "pstree available"             "command -v pstree"
check "killall available"            "command -v killall"
check "expect available"             "command -v expect"
check "sponge available"             "command -v sponge"
check "ts available"                 "command -v ts"
check "rename available"             "command -v rename"
check "entr available"               "command -v entr"
check "jo available"                 "command -v jo"
check "whois available"              "command -v whois"
check "sqlite3 available"           "command -v sqlite3"
check "atop available"               "command -v atop"
check "etckeeper available"          "command -v etckeeper"
check "tftpd available"              "test -x /usr/sbin/in.tftpd"
check "mount.cifs available"        "test -x /usr/sbin/mount.cifs"
check "nfs client available"        "test -x /usr/sbin/mount.nfs"
check "sshfs available"              "command -v sshfs"
check "getfacl available"           "command -v getfacl"
check "getfattr available"          "command -v getfattr"
check "wg available"                "command -v wg"
check "conntrack available"         "command -v conntrack"
check "ipset available"             "command -v ipset"
check "ltrace available"            "command -v ltrace"
check "pv available"                "command -v pv"
check "hexdump available"           "command -v hexdump"
check "xxd available"               "command -v xxd"
check "pystrings available"         "test -x /usr/local/bin/pystrings"
check "strings alternative"         "update-alternatives --display strings"
check "pyhttpd available"           "test -x /usr/local/bin/pyhttpd"
check "httpd alternative"           "update-alternatives --display httpd"
echo ""

# ── System configuration ────────────────────────────────────────────
echo "System:"
check "sshd enabled"                "systemctl is-enabled ssh"
check "root login disabled"         "grep -q '^PermitRootLogin no' /etc/ssh/sshd_config"
check "password auth disabled"      "grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config"
check "machine-id empty"            "test ! -s /etc/machine-id"
check "dpkg doc exclusions"         "test -f /etc/dpkg/dpkg.cfg.d/01-nodoc"
check "qemu-guest-agent available"  "test -x /usr/sbin/qemu-ga"
echo ""

# ── Rootless Podman config ──────────────────────────────────────────
echo "Rootless Podman:"
check "subuid configured"           "grep -q '^agent:' /etc/subuid"
check "subgid configured"           "grep -q '^agent:' /etc/subgid"
check "storage.conf exists"         "test -f /home/agent/.config/containers/storage.conf"
echo ""

# ── Summary ─────────────────────────────────────────────────────────
echo "==============================="
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
