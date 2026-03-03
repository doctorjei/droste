# Droste

Nested virtualization VM images for testing infrastructure operations — containers, VMs, DRBD, Pacemaker, iSCSI, LXC, Proxmox VE, and more. Built as layered QCOW2 images on top of Debian 12 genericcloud.

## Tiers

Each tier builds on the previous one, adding tools for progressively more complex infrastructure scenarios.

| Tier | Based on | Focus | Size |
|------|----------|-------|------|
| **thread** | debian-12-genericcloud | Basic tools, containers, networking | 444 MB |
| **yarn** | thread | VM management, storage, nested virt | 691 MB |
| **fabric** | yarn | HA clustering, DRBD, iSCSI, Ceph | 832 MB |
| **tapestry** | fabric | Testing, benchmarking, security, observability | 1.1 GB |
| **loom** | tapestry | C/C++ development toolchain | 1.3 GB |
| **jacquard** | loom | Proxmox VE (PVE kernel, ZFS, corosync) | 2.2 GB |

Pick the smallest tier that has what you need. Most container and networking work only needs **thread**. VM-in-VM testing needs **yarn**. Cluster or HA testing needs **fabric**.

Each image includes an `agent` user (UID 1000) with passwordless sudo and key-only SSH. See [BUILDING.md](BUILDING.md) for build and test instructions.

## droste-thread: Basic Tools & Container Tools
*(based on debian-12-genericcloud)*

### Tools in addition to base image

**Applications**: ```atop, bc, dnstop, htop, iftop, iotop, smbclient, sqlite3, tmux```

**Filesystems**: ```acl, attr, cifs-utils, fatrace, inotify-tools, lsof, nfs-common, sshfs```

**General Utilities**: ```bsdextrautils, crudini, debootstrap, entr, expect, file, jo, jq, ltrace, make, moreutils, parallel, patch, psmisc, pv, pystrings (strings), rename, strace, sysstat, tree, unzip, xmlstarlet, xxd, zip```

**Networking**: ```conntrack, curl, dnsmasq, dnsutils, fping, git, inetutils-telnet, ipcalc, iproute2, ipset, iputils-arping, ipvsadm, netcat-openbsd, nftables, pipx, pyhttpd (httpd), rsync, socat, ssh-import-id, sshpass, tftpd-hpa, wget, whois, wireguard-tools```

**Virtualization**: ```fuse-overlayfs, lxc, lxcfs, podman, qemu-guest-agent, slirp4netns, systemd-container, uidmap```

**System Tools**: ```etckeeper, locales, molly-guard, watchdog```

## droste-yarn: VM Management & Storage
*(based on droste-thread)*

### Tools in addition to droste-thread

**Applications**: ```bmon, ncdu, nethogs, picocom```

**Networking**: ```bridge-utils, ethtool, hping3, nicstat```

**Storage**: ```btrfs-progs, cryptsetup, dosfstools, gdisk, lvm2, mdadm, mtools, nbd-client, nfs-kernel-server, ntfs-3g, parted, quota, squashfs-tools, thin-provisioning-tools```

**Virtualization**: ```cloud-image-utils, cpu-checker, libvirt-daemon-system, nbdkit, ovmf, qemu-system-x86, qemu-utils, swtpm, virtinst```

**General Utilities**: ```ansible, dmidecode, gettext-base, hdparm, lshw, pciutils, sysbench```

**System Tools**: ```cpufrequtils, irqbalance```

## droste-fabric: High Availability & Clustering
*(based on droste-yarn)*

### Tools in addition to droste-yarn

**High Availability**: ```fence-agents, keepalived, pacemaker, pacemaker-cli-utils, pcs, resource-agents, sbd```

**Cluster**: ```clustershell, dlm-controld```

**Storage**: ```ceph-common, drbd-utils, multipath-tools, open-iscsi, targetcli-fb```

**Networking**: ```ebtables, syslinux-common```

**System Tools**: ```numactl```

## droste-tapestry: Testing, Security & Observability
*(based on droste-fabric)*

### Tools in addition to droste-fabric

**Applications**: ```lnav```

**Benchmarking**: ```apache2-utils, fio, iperf3, stress-ng```

**Networking**: ```arp-scan, bird2, haproxy, nmap, openvswitch-switch, tcpreplay```

**Security**: ```aide, apparmor-utils, auditd, fail2ban, lynis```

**Storage**: ```blktrace, sg3-utils, smartmontools, xorriso```

**Virtualization**: ```buildah, qemu-system-arm, skopeo```

**Observability**: ```prometheus-node-exporter```

**Clients**: ```postgresql-client, redis-tools```

**Hardware**: ```ipmitool```

## droste-loom: C/C++ Development Toolchain
*(based on droste-tapestry)*

### Tools in addition to droste-tapestry

**Compilers**: ```build-essential```

**Build Systems**: ```autoconf, automake, cmake, libtool, ninja-build, pkg-config```

**Debugging**: ```gdb, valgrind```

**General Utilities**: ```bear, ccache```

## droste-jacquard: Proxmox VE Environment
*(based on droste-loom)*

### Tools in addition to droste-loom

**Proxmox VE**: ```proxmox-ve, zfsutils-linux```
