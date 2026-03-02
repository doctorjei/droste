#!/usr/bin/env bash
# Smoke test a running droste-thread instance over SSH.
#
# Connects to the guest and verifies that all expected tools, users,
# and configuration are present and working.
#
# Usage:
#   scripts/smoke-test.sh
#   scripts/smoke-test.sh --port 2222 --user agent --host localhost
set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────
HOST="localhost"
PORT=2222
USER="agent"
SSH_KEY=""

# ── Usage ───────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Smoke test a running droste-thread instance over SSH.

Options:
  --host HOST      Guest hostname or IP (default: localhost)
  --port PORT      SSH port (default: 2222)
  --user USER      SSH user (default: agent)
  --ssh-key FILE   Path to SSH private key (default: ssh default)
  -h, --help       Show this help message
EOF
}

# ── Parse arguments ─────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)    HOST="$2"; shift 2 ;;
        --port)    PORT="$2"; shift 2 ;;
        --user)    USER="$2"; shift 2 ;;
        --ssh-key) SSH_KEY="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)         echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# ── Build SSH command ───────────────────────────────────────────────
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
SSH_OPTS+=(-p "$PORT")
if [[ -n "$SSH_KEY" ]]; then
    SSH_OPTS+=(-i "$SSH_KEY")
fi

ssh_run() {
    ssh "${SSH_OPTS[@]}" "${USER}@${HOST}" "$@"
}

# ── Test framework ──────────────────────────────────────────────────
PASS=0
FAIL=0
ERRORS=()

check() {
    local description="$1"
    shift
    if ssh_run "$@" &>/dev/null; then
        echo "  + $description"
        PASS=$((PASS + 1))
    else
        echo "  - FAIL: $description"
        ERRORS+=("$description")
        FAIL=$((FAIL + 1))
    fi
}

# ── Connectivity ────────────────────────────────────────────────────
echo "droste-thread smoke test"
echo "======================"
echo ""
echo "Target: ${USER}@${HOST}:${PORT}"
echo ""

echo "Connectivity:"
if ! ssh_run true; then
    echo "  - FAIL: cannot connect to ${USER}@${HOST}:${PORT}"
    echo ""
    echo "Results: 0 passed, 1 failed"
    exit 1
fi
echo "  + SSH connection"
PASS=1
echo ""

# ── User and permissions ────────────────────────────────────────────
echo "User:"
check "agent user exists with UID 1000"    "test \$(id -u) -eq 1000"
check "agent group"                         "id -gn | grep -q agent"
check "passwordless sudo"                   "sudo -n true"
echo ""

# ── Container tools ─────────────────────────────────────────────────
echo "Containers:"
check "lxc-create available"    "lxc-create --version"
check "podman available"        "podman --version"
check "podman info runs"        "podman info --format '{{.Host.OS}}'"
check "fuse-overlayfs available" "fuse-overlayfs --version"
check "slirp4netns available"   "slirp4netns --version"
check "systemd-nspawn available" "command -v systemd-nspawn"
check "machinectl available"   "command -v machinectl"
echo ""

# ── Networking ──────────────────────────────────────────────────────
echo "Networking:"
check "iproute2 (ip command)"       "ip -V"
check "dnsmasq available"           "test -x /usr/sbin/dnsmasq"
check "nftables available"          "sudo nft --version"
check "ipcalc available"            "ipcalc --version"
check "ipvsadm available"           "sudo ipvsadm --version"
check "IPv4 forwarding enabled"     "test \$(cat /proc/sys/net/ipv4/ip_forward) -eq 1"
check "IPv6 forwarding enabled"     "test \$(cat /proc/sys/net/ipv6/conf/all/forwarding) -eq 1"
echo ""

# ── Utilities ───────────────────────────────────────────────────────
echo "Utilities:"
check "curl available"      "curl --version"
check "jq available"        "jq --version"
check "rsync available"     "rsync --version"
check "tmux available"      "tmux -V"
check "smbclient available" "smbclient --version"
check "git available"       "git --version"
check "wget available"      "wget --version"
check "make available"      "make --version"
check "file available"      "file --version"
check "nc available"        "command -v nc"
check "dig available"       "dig -v"
check "tree available"      "tree --version"
check "unzip available"     "unzip -v"
check "zip available"       "zip --version"
check "pipx available"      "pipx --version"
check "htop available"      "htop --version"
check "patch available"     "patch --version"
check "bc available"        "echo quit | bc"
check "telnet available"    "command -v telnet"
check "ssh-import-id available" "command -v ssh-import-id"
check "molly-guard available"   "test -x /usr/lib/molly-guard/molly-guard"
check "debootstrap available"   "test -x /usr/sbin/debootstrap"
check "sshpass available"       "sshpass -V"
check "xmlstarlet available"    "xmlstarlet --version"
check "lsof available"          "lsof -v"
check "strace available"        "strace --version"
check "sar available"           "sar -V"
check "iotop available"         "test -x /usr/sbin/iotop"
check "iftop available"         "test -x /usr/sbin/iftop"
check "pstree available"        "pstree --version"
check "killall available"       "command -v killall"
check "expect available"        "expect -v"
check "sponge available"       "command -v sponge"
check "ts available"           "command -v ts"
check "rename available"       "command -v rename"
check "entr available"         "command -v entr"
check "jo available"           "jo -v"
check "whois available"        "command -v whois"
check "sqlite3 available"     "sqlite3 --version"
check "atop available"         "atop -V"
check "etckeeper available"   "command -v etckeeper"
check "tftpd available"       "test -x /usr/sbin/in.tftpd"
check "mount.cifs available"    "test -x /usr/sbin/mount.cifs"
check "nfs client available"    "test -x /usr/sbin/mount.nfs"
check "sshfs available"         "sshfs --version"
check "getfacl available"       "getfacl --version"
check "getfattr available"      "getfattr --version"
check "wg available"            "wg --version"
check "socat available"          "socat -V"
check "fping available"          "fping --version"
check "arping available"         "command -v arping"
check "parallel available"       "parallel --version"
check "watchdog available"       "test -x /usr/sbin/watchdog"
check "dnstop available"         "command -v dnstop"
check "fatrace available"        "test -x /usr/sbin/fatrace"
check "crudini available"        "crudini --version"
check "lxcfs available"          "command -v lxcfs"
check "inotifywait available"    "command -v inotifywait"
check "conntrack available"     "sudo conntrack --version"
check "ipset available"         "sudo ipset --version"
check "ltrace available"        "ltrace --version"
check "pv available"            "pv --version"
check "hexdump available"       "hexdump --version"
check "xxd available"           "xxd --version"
check "strings available"       "strings --help"
check "httpd available"         "command -v httpd"
echo ""

# ── System configuration ────────────────────────────────────────────
echo "System:"
check "sshd running"                    "sudo systemctl is-active ssh"
check "root login disabled"             "grep -q '^PermitRootLogin no' /etc/ssh/sshd_config"
check "password auth disabled"          "grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config"
check "machine-id populated (cloud-init ran)"   "test -s /etc/machine-id"
check "qemu-guest-agent available"             "test -x /usr/sbin/qemu-ga"
echo ""

# ── Rootless Podman config ──────────────────────────────────────────
echo "Rootless Podman:"
check "subuid configured"       "grep -q '^agent:' /etc/subuid"
check "subgid configured"       "grep -q '^agent:' /etc/subgid"
check "storage.conf exists"     "test -f ~/.config/containers/storage.conf"
echo ""

# ── Summary ─────────────────────────────────────────────────────────
echo "================================"
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "Failures:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi
