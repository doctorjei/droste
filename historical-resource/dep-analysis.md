# Transitive Dependency Analysis — Droste Tapestry Tier Candidates

**Date:** 2026-03-01
**Method:** Manual recursive trace via packages.debian.org/bookworm, amd64 architecture
**Build setting:** `install_recommends: false`

## Key Assumptions — Already Installed in Lower Tiers

The following libraries are confirmed present through lower-tier transitive chains
(beyond the explicit list provided):

| Library | Pulled by |
|---------|-----------|
| libgmp10 (855 kB inst) | libgnutls30 |
| libhogweed6 (463 kB inst) | libgnutls30 |
| libnettle8 (520 kB inst) | libgnutls30 |
| libbrotli1 (783 kB inst) | libcurl4 |
| libnghttp2-14 (220 kB inst) | libcurl4 |
| libldap-2.5-0 (553 kB inst) | libcurl4 |
| libbz2-1.0 (106 kB inst) | base system (debootstrap) |
| libncursesw6 (412 kB inst) | base system (bash/htop/etc) |
| liblzma5 | base system |
| libkmod2 | base system |
| libgdbm6 (129 kB inst) | perl -> libperl5.36 |
| libgdbm-compat4 (70 kB inst) | perl -> libperl5.36 |
| libevent-core-2.1-7 (302 kB inst) | tmux |
| libcurl3-gnutls (828 kB inst) | ceph-common (fabric) |
| python3-yaml (493 kB inst) | ansible (full) |
| libyaml-0-2 (152 kB inst) | python3-yaml -> ansible (full) |
| libssh-gcrypt-4 (637 kB inst) | wireshark/bird2 — NOT in lower tiers |
| libevent-2.1-7 (435 kB inst) | NOT in lower tiers (tmux uses libevent-core only) |
| libcap2-bin (133 kB inst) | wireshark-common — NOT in lower tiers necessarily |
| libaio1 | qemu-system-x86 (full) |
| libnuma1 | qemu-system-x86 (full) |
| libpmem1 | qemu-system-x86 (full) |
| librados2, librbd1 | ceph-common (fabric) |
| libnbd0 | nbdkit (full) |
| libnl-3-200, libnl-genl-3-200 | quota (full) |
| libsasl2-2 | qemu-system-x86 (full) |
| libpng16-16 | qemu-system-x86 (full) |
| libjpeg62-turbo | qemu-system-x86 (full) |
| libfuse3-3 | qemu-system-x86 (full) |

---

## GROUP A — Accepted Packages, Dependency Verification

---

### 1. openvswitch-switch (+ openvswitch-common)

**What:** Software-defined networking switch (OpenFlow, VXLAN, GRE tunnels)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| openvswitch-switch | 1,654 | 8,194 |
| openvswitch-common | 1,869 | 12,850 |
| python3-openvswitch | 904 | 3,249 |
| python3-netifaces | 17 | 53 |
| python3-sortedcontainers | 31 | 159 |
| libunbound8 | 540 | 1,236 |
| libevent-2.1-7 | 176 | 435 |
| libxdp1 | 55 | 358 |
| libbpf1 | 142 | 385 |
| uuid-runtime | ~50 | ~150 |
| **TOTAL NEW** | **~5,438** | **~27,069** |

**Notes:**
- libunbound8 needs libevent-2.1-7 (full, not core). libbpf1 and libxdp1 are eBPF libs.
- libnuma1, libssl3, libcap-ng0, python3 already in base.
- libgmp10, libhogweed6, libnettle8 are needed by libunbound8 but already in base via libgnutls30.
- **WARNING: ~27 MB installed is substantial.**

---

### 2. tshark

**What:** CLI network protocol analyzer (Wireshark without GUI)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| tshark | 159 | 396 |
| wireshark-common | 472 | 1,386 |
| libwireshark16 | 17,432 | 110,907 |
| libwireshark-data | 1,618 | 7,701 |
| libwiretap13 | 240 | 696 |
| libwsutil14 | 98 | 262 |
| liblua5.2-0 | 109 | 439 |
| libc-ares2 | 100 | 169 |
| libbcg729-0 | 32 | 76 |
| libsbc1 | 31 | 89 |
| libsmi2ldbl | 120 | 445 |
| libsnappy1v5 | 25 | 89 |
| libspandsp2 | 275 | 857 |
| libtiff6 | 309 | 716 |
| libdeflate0 | 60 | 161 |
| libjbig0 | 31 | 84 |
| liblerc4 | 166 | 649 |
| libwebp7 | 279 | 544 |
| libmaxminddb0 | 29 | 76 |
| libspeexdsp1 | 40 | 95 |
| libssh-gcrypt-4 | 215 | 637 |
| libcap2-bin | 34 | 133 |
| **TOTAL NEW** | **~21,874** | **~126,597** |

**CRITICAL WARNING: ~127 MB installed. libwireshark16 alone is 111 MB.**
- libnghttp2-14 already in base via libcurl4.
- libbrotli1 already in base via libcurl4.
- libjpeg62-turbo already in full via qemu.
- libtiff6 pulls libdeflate0 + libjbig0 + liblerc4 + libwebp7 (image format chain via libspandsp2).
- libssh-gcrypt-4 is shared with bird2.
- libcap2-bin is shared with fping, iputils-arping.
- **This is by far the most expensive package in the list.**

---

### 3. qemu-system-arm

**What:** ARM system emulator (complements qemu-system-x86 already in full tier)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| qemu-system-arm | 8,719 | 42,849 |
| **TOTAL NEW** | **~8,719** | **~42,849** |

**Notes:**
- ALL dependencies are already satisfied by qemu-system-x86 in the full tier:
  qemu-system-common, qemu-system-data, libaio1, libcapstone4, libfdt1, libfuse3-3,
  libglib2.0-0, libgmp10, libgnutls30, libhogweed6, libibverbs1, libjpeg62-turbo,
  libnettle8, libnuma1, libpixman-1-0, libpmem1, libpng16-16, librdmacm1, libsasl2-2,
  libseccomp2, libslirp0, liburing2, libvdeplug2, libzstd1.
- **Pure binary cost — no new deps at all.**

---

### 4. nmap

**What:** Network discovery and security auditing tool

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| nmap | 1,853 | 4,434 |
| nmap-common | 4,051 | 21,188 |
| liblinear4 | 43 | 102 |
| liblua5.3-0 | 120 | 495 |
| lua-lpeg | 37 | 252 |
| libblas3 | 145 | 464 |
| **TOTAL NEW** | **~6,249** | **~26,935** |

**Notes:**
- nmap-common is 21 MB (scripts, fingerprint DBs, etc.) — this is unavoidable data.
- liblua5.3-0 is SHARED with haproxy.
- libpcre3, libssh2-1, libpcap0.8 already in base/lite.
- libblas3 is pulled by liblinear4 (machine learning classification lib for nmap).

---

### 5. haproxy

**What:** Fast, reliable TCP/HTTP load balancer and reverse proxy

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| haproxy | 1,995 | 4,223 |
| liblua5.3-0 | 120 | 495 |
| libopentracing-c-wrapper0 | 29 | 100 |
| libopentracing1 | 52 | 197 |
| **TOTAL NEW** | **~2,196** | **~5,015** |

**Notes:**
- liblua5.3-0 SHARED with nmap (pay once).
- libssl3, libpcre2-8-0, libsystemd0, libcrypt1 already in base.
- libopentracing chain is small (~297 kB installed).
- If nmap is also installed, haproxy incremental is only ~4,520 kB inst.

---

### 6. ipmitool

**What:** CLI utility for managing IPMI-capable devices (BMC, server management)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| ipmitool | 1,956 | 6,290 |
| libfreeipmi17 | 1,012 | 5,615 |
| freeipmi-common | 345 | 517 |
| **TOTAL NEW** | **~3,313** | **~12,422** |

**Notes:**
- libfreeipmi17 is the main dep cost (5.6 MB inst).
- libreadline8, libssl3, libgcrypt20 already in base.
- No surprising transitive deps.

---

### 7. fio

**What:** Flexible I/O benchmark tool (disk, network I/O stress testing)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| fio | 525 | 2,129 |
| libgfapi0 | 3,084 | 3,234 |
| libglusterfs0 | 3,268 | 3,957 |
| libgfrpc0 | 3,058 | 3,271 |
| libgfxdr0 | 3,033 | 3,109 |
| libpmemblk1 | 74 | 182 |
| libdaxctl1 | 21 | 68 |
| libndctl6 | 60 | 214 |
| **TOTAL NEW** | **~13,123** | **~16,164** |

**CRITICAL WARNING: GlusterFS libs are ~13.6 MB installed!**
- libgfapi0 pulls the entire GlusterFS client library stack (libglusterfs0 + libgfrpc0 + libgfxdr0).
- libaio1, libnuma1, libpmem1, libibverbs1, librdmacm1, librados2, librbd1, libnbd0 already in full/fabric tiers.
- libpmemblk1 is small (adds libdaxctl1 + libndctl6).
- **Consider: if GlusterFS is not needed, fio could potentially be compiled without gluster support, but the Debian package has it compiled in.**

---

### 8. stress-ng

**What:** Stress testing tool (CPU, memory, I/O, network, many subsystems)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| stress-ng | 2,308 | 8,836 |
| libipsec-mb1 | 959 | 12,515 |
| libjudydebian1 | 99 | 337 |
| libsctp1 | 29 | 56 |
| libxxhash0 | 27 | 99 |
| libegl1 | 33 | 111 |
| libegl-mesa0 | 112 | 324 |
| libgbm1 | 37 | 107 |
| libgles2 | 16 | 105 |
| libglvnd0 | 51 | 728 |
| libglapi-mesa | 35 | 268 |
| libdrm2 | 37 | 121 |
| libdrm-common | 7 | 42 |
| libwayland-server0 | 35 | 111 |
| libwayland-client0 | 28 | 89 |
| libx11-xcb1 | 188 | 252 |
| libx11-6 | 742 | 1,562 |
| libx11-data | 285 | 1,577 |
| libxcb1 | 141 | 296 |
| libxcb-dri2-0 | 104 | 136 |
| libxcb-dri3-0 | 104 | 136 |
| libxcb-present0 | 103 | 126 |
| libxcb-randr0 | 114 | 192 |
| libxcb-sync1 | 106 | 145 |
| libxcb-xfixes0 | 107 | 151 |
| libxshmfence1 | 9 | 26 |
| libxau6 | 19 | 42 |
| libxdmcp6 | 26 | 53 |
| **TOTAL NEW** | **~5,961** | **~28,693** |

**CRITICAL WARNING: Pulls Mesa/EGL/X11 stack (~6.5 MB installed) + libipsec-mb1 (12.5 MB installed)!**
- libegl1 -> libegl-mesa0 -> libgbm1 -> libdrm2 + libwayland-server0 + libx11-xcb1 -> libx11-6 -> libxcb1 -> X11 chain
- libipsec-mb1 is Intel IPsec crypto library (12.5 MB installed!) for stress-ng crypto tests.
- libsctp1 is SHARED with iperf3.
- libjpeg62-turbo already in full tier.
- libapparmor1, libbsd0, libcrypt1, libkmod2 already in base.
- **28.7 MB installed is very high for a stress tester.**

---

### 9. sg3-utils

**What:** Utilities for SCSI devices (disk diagnostics, SAS/SSD management)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| sg3-utils | 825 | 2,802 |
| libsgutils2-1.46-2 | 114 | 319 |
| **TOTAL NEW** | **~939** | **~3,121** |

**Notes:** Very clean. Only libc6 needed transitively. Excellent cost/value.

---

### 10. bird2

**What:** Internet routing daemon (BGP, OSPF, RIP, BFD)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| bird2 | 735 | 1,553 |
| libssh-gcrypt-4 | 215 | 637 |
| **TOTAL NEW** | **~950** | **~2,190** |

**Notes:**
- libssh-gcrypt-4 is SHARED with tshark (via wireshark-common).
- libreadline8, libtinfo6, ucf already in base.
- libgcrypt20, libgpg-error0, libgssapi-krb5-2 already in base.
- Very clean and lightweight.

---

### 11. smartmontools

**What:** SMART disk monitoring and self-test tools

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| smartmontools | 579 | 2,199 |
| **TOTAL NEW** | **~579** | **~2,199** |

**Notes:** Zero new deps. All deps (libc6, libcap-ng0, libselinux1, libstdc++6, libsystemd0, libgcc-s1) already in base. Excellent.

---

### 12. apache2-utils

**What:** HTTP benchmarking (ab), password hashing (htpasswd), log rotation

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| apache2-utils | 210 | 444 |
| libapr1 | 100 | 288 |
| libaprutil1 | 86 | 280 |
| **TOTAL NEW** | **~396** | **~1,012** |

**Notes:**
- libaprutil1 depends on libdb5.3, libexpat1, libgdbm6, libssl3, libcrypt1 — all in base.
- libapr1 depends on libc6, libuuid1 — in base.
- Very lightweight. Clean.

---

### 13. iperf3

**What:** TCP/UDP bandwidth measurement tool

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| iperf3 | 33 | 86 |
| libiperf0 | 89 | 252 |
| libsctp1 | 29 | 56 |
| **TOTAL NEW** | **~151** | **~394** |

**Notes:**
- libsctp1 is SHARED with stress-ng.
- Extremely lightweight. Outstanding cost/value.

---

### 14. buildah

**What:** OCI container image builder (Dockerfile-compatible, daemonless)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| buildah | 6,001 | 20,370 |
| **TOTAL NEW** | **~6,001** | **~20,370** |

**Notes:**
- **Static Go binary.** All deps already satisfied by podman in lite tier:
  golang-github-containers-common, libdevmapper1.02.1, libgpgme11, libseccomp2, uidmap.
- The 20.4 MB installed is the Go binary itself. No transitive dep surprises.

---

### 15. skopeo

**What:** Container image inspection/copy tool (works with registries, no daemon)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| skopeo | 4,650 | 15,951 |
| **TOTAL NEW** | **~4,650** | **~15,951** |

**Notes:**
- **Static Go binary.** All deps already satisfied by podman in lite tier:
  golang-github-containers-common, libdevmapper1.02.1, libgpgme11.
- Pure binary cost, no new transitive deps.

---

### 16. prometheus-node-exporter

**What:** Machine metrics exporter for Prometheus (CPU, memory, disk, network)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| prometheus-node-exporter | 3,984 | 13,465 |
| **TOTAL NEW** | **~3,984** | **~13,465** |

**Notes:**
- **Static Go binary.** Only depends on libc6, adduser, init-system-helpers.
- Recommends `dbus` and `prometheus-node-exporter-collectors` but with install_recommends: false those are skipped.
- Pure binary cost.

---

### 17. postgresql-client (postgresql-client-15)

**What:** PostgreSQL CLI client (psql) for database management

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| postgresql-client-15 | 1,701 | 8,244 |
| libpq5 | 191 | 864 |
| postgresql-client-common | 34 | 130 |
| **TOTAL NEW** | **~1,926** | **~9,238** |

**Notes:**
- libpq5 needs libldap-2.5-0 (already in base via libcurl4), libgssapi-krb5-2 (base), libssl3 (base).
- libreadline8, liblz4-1, libzstd1, sensible-utils, perl — all in base.
- Clean dependency chain.

---

### 18. lnav

**What:** Advanced log file navigator with SQL queries, syntax highlighting

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| lnav | 2,529 | 7,868 |
| **TOTAL NEW** | **~2,529** | **~7,868** |

**Notes:**
- ALL deps already in lower tiers: libarchive13 (lite), libcurl3-gnutls (fabric/via ceph),
  libncursesw6 (base), libpcre2-8-0 (base), libreadline8 (base), libsqlite3-0 (base),
  libbz2-1.0 (base), libtinfo6 (base), libstdc++6 (base), libgcc-s1 (base).
- Zero new transitive deps. Pure binary cost.

---

### 19. redis-tools

**What:** Redis CLI client and benchmark tool

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| redis-tools | 968 | 5,837 |
| libjemalloc2 | 269 | 872 |
| liblzf1 | 10 | 39 |
| libatomic1 | 9 | 45 |
| **TOTAL NEW** | **~1,256** | **~6,793** |

**Notes:**
- libjemalloc2 (high-perf memory allocator) is the main new dep.
- libssl3, libsystemd0 already in base.
- Clean and reasonable.

---

### 20. fail2ban

**What:** Intrusion prevention — bans IPs after repeated auth failures

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| fail2ban | 441 | 2,129 |
| **TOTAL NEW** | **~441** | **~2,129** |

**Notes:**
- Pure Python. Only depends on python3 (already in base).
- Recommends python3-pyinotify, python3-systemd, nftables, whois — all skipped or already present.
- Extremely lightweight.

---

### 21. lynis

**What:** Security auditing and hardening scanner

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| lynis | 259 | 1,658 |
| **TOTAL NEW** | **~259** | **~1,658** |

**Notes:**
- Shell script. Only depends on e2fsprogs (already in base).
- Zero new transitive deps. Outstanding cost/value.

---

### 22. xorriso

**What:** ISO 9660 filesystem creation/manipulation/extraction tool

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| xorriso | 315 | 348 |
| libisoburn1 | 392 | 1,057 |
| libisofs6 | 204 | 490 |
| libburn4 | 162 | 363 |
| libjte2 | 29 | 74 |
| **TOTAL NEW** | **~1,102** | **~2,332** |

**Notes:**
- libbz2-1.0 and libreadline8 already in base.
- libacl1, zlib1g already in base.
- Clean chain of ISO/burn libraries. No surprises.

---

### 23. apparmor-utils

**What:** AppArmor profile management utilities (aa-genprof, aa-logprof, aa-complain)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| apparmor-utils | 92 | 377 |
| apparmor | 602 | 2,567 |
| python3-apparmor | 86 | 471 |
| python3-libapparmor | 36 | 151 |
| **TOTAL NEW** | **~816** | **~3,566** |

**Notes:**
- libapparmor1 already in base (podman dependency).
- python3 already in base.
- libc6 already in base.
- Moderate cost.

---

### 24. aide (+ aide-common)

**What:** Advanced Intrusion Detection Environment — file integrity checker

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| aide | 131 | 293 |
| aide-common | 105 | 451 |
| libmhash2 | 92 | 201 |
| liblockfile1 | 17 | 45 |
| liblockfile-bin | 20 | 53 |
| **TOTAL NEW** | **~365** | **~1,043** |

**Notes:**
- libacl1, libaudit1, libcap2, libext2fs2, libpcre2-8-0, libselinux1, zlib1g — all in base.
- ucf in base.
- Very clean. libmhash2 (hash algorithms) is the only notable new dep.

---

### 25. auditd

**What:** Linux audit daemon — kernel-level security event logging

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| auditd | 213 | 745 |
| libauparse0 | 60 | 167 |
| libwrap0 | 54 | 110 |
| **TOTAL NEW** | **~327** | **~1,022** |

**Notes:**
- libaudit1, libcap-ng0, libgssapi-krb5-2, libkrb5-3, mawk — all in base.
- libnsl2 in base.
- Very clean.

---

### 26. blktrace

**What:** Block device I/O tracing tool (trace disk I/O at kernel level)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| blktrace | 754 | 1,072 |
| **TOTAL NEW** | **~754** | **~1,072** |

**Notes:**
- libaio1 already in full tier (qemu-system-x86). python3 in base.
- Zero new deps. Pure binary.

---

### 27. arp-scan

**What:** ARP-based network scanner (discover hosts on local network)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| arp-scan | 476 | 1,567 |
| **TOTAL NEW** | **~476** | **~1,567** |

**Notes:**
- libcap2, libpcap0.8 already in base.
- Zero new deps. Clean.

---

### 28. tcpreplay

**What:** Replay and edit pcap files on the network

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| tcpreplay | 318 | 1,962 |
| libdumbnet1 | 27 | 94 |
| **TOTAL NEW** | **~345** | **~2,056** |

**Notes:**
- libpcap0.8 already in base.
- libdumbnet1 is tiny (94 kB).
- Very clean.

---

## GROUP B — Candidates Needing Decision

---

### 29. fping

**What:** Fast parallel ping tool (multiple hosts simultaneously)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| fping | 40 | 93 |
| libcap2-bin | 34 | 133 |
| **TOTAL NEW** | **~74** | **~226** |

**Notes:**
- libcap2-bin is SHARED with tshark, iputils-arping.
- netbase already in base.
- Exceptionally lightweight.

---

### 30. iputils-arping

**What:** Send ARP requests to discover hosts and detect duplicates

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| iputils-arping | 20 | 50 |
| libcap2-bin | 34 | 133 |
| **TOTAL NEW** | **~54** | **~183** |

**Notes:**
- libcap2, libcap2-bin already covered if tshark or fping installed.
- Tiny.

---

### 31. parallel (GNU parallel)

**What:** Shell tool for executing jobs in parallel across cores or hosts

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| parallel | 1,829 | 2,894 |
| **TOTAL NEW** | **~1,829** | **~2,894** |

**Notes:**
- perl, procps, sysstat all already in base/lite.
- Zero new deps. Pure script (Perl-based). Clean.

---

### 32. watchdog

**What:** Hardware/software watchdog daemon (automatic reboot on hang)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| watchdog | 68 | 229 |
| **TOTAL NEW** | **~68** | **~229** |

**Notes:**
- debconf, udev already in base.
- Incredibly lightweight. Zero new deps.

---

### 33. clustershell

**What:** Parallel command execution framework for cluster administration

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| clustershell | 48 | 95 |
| python3-clustershell | 127 | 631 |
| **TOTAL NEW** | **~175** | **~726** |

**Notes:**
- python3-yaml already in full tier (via ansible).
- libyaml-0-2 already in full tier.
- python3 in base.
- Very lightweight.

---

### 34. sysbench

**What:** Multi-threaded benchmark tool (CPU, memory, I/O, MySQL/PostgreSQL)

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| sysbench | 111 | 353 |
| libluajit2-5.1-2 | 252 | 597 |
| libluajit2-5.1-common | 46 | 218 |
| libmariadb3 | 177 | 561 |
| mariadb-common | 26 | 67 |
| mysql-common | 7 | 33 |
| libpq5 | 191 | 864 |
| **TOTAL NEW** | **~810** | **~2,693** |

**Notes:**
- libaio1 already in full tier.
- libpq5 is SHARED with postgresql-client-15 (pay once).
- If postgresql-client is installed, sysbench incremental drops to ~1,829 kB inst.
- libmariadb3 chain (mariadb-common -> mysql-common) is small.
- libluajit2 is the LuaJIT compiler (~815 kB installed with common files).
- Reasonable cost.

---

### 35. gddrescue

**What:** Data recovery tool — copies data from failing block devices

| Component | DL (kB) | Inst (kB) |
|-----------|---------|-----------|
| gddrescue | 137 | 435 |
| **TOTAL NEW** | **~137** | **~435** |

**Notes:**
- libc6, libgcc-s1, libstdc++6 all in base.
- Zero new deps. Incredibly lightweight.

---

## SHARED DEPENDENCY OVERLAP MATRIX

Dependencies that appear in multiple packages from this list, paid only once:

| Shared Dependency | Inst (kB) | Packages Sharing It |
|-------------------|-----------|---------------------|
| liblua5.3-0 | 495 | nmap, haproxy |
| libsctp1 | 56 | iperf3, stress-ng |
| libssh-gcrypt-4 | 637 | tshark (wireshark-common), bird2 |
| libcap2-bin | 133 | tshark (wireshark-common), fping, iputils-arping |
| libpq5 | 864 | postgresql-client-15, sysbench |
| libevent-2.1-7 | 435 | openvswitch-switch (via libunbound8) |
| libbpf1 | 385 | openvswitch-switch/common |
| libxdp1 | 358 | openvswitch-switch/common |
| libdumbnet1 | 94 | tcpreplay |
| libatomic1 | 45 | redis-tools |

---

## COST SUMMARY TABLE (sorted by total installed size)

| # | Package | Own Inst (kB) | New Deps Inst (kB) | Total Incr (kB) | Total Incr (MB) | Description |
|---|---------|---------------|---------------------|------------------|-----------------|-------------|
| 2 | tshark | 396 | 126,201 | **126,597** | **123.6** | CLI protocol analyzer (Wireshark engine) |
| 3 | qemu-system-arm | 42,849 | 0 | **42,849** | **41.8** | ARM system emulator |
| 8 | stress-ng | 8,836 | 19,857 | **28,693** | **28.0** | Multi-subsystem stress tester |
| 1 | openvswitch-switch | 8,194 | 18,875 | **27,069** | **26.4** | Software-defined networking switch |
| 4 | nmap | 4,434 | 22,501 | **26,935** | **26.3** | Network scanner and auditor |
| 14 | buildah | 20,370 | 0 | **20,370** | **19.9** | OCI container image builder |
| 7 | fio | 2,129 | 14,035 | **16,164** | **15.8** | Flexible I/O benchmark |
| 15 | skopeo | 15,951 | 0 | **15,951** | **15.6** | Container image copy/inspect |
| 16 | prom-node-exporter | 13,465 | 0 | **13,465** | **13.2** | Prometheus machine metrics |
| 6 | ipmitool | 6,290 | 6,132 | **12,422** | **12.1** | IPMI device management |
| 17 | postgresql-client | 8,244 | 994 | **9,238** | **9.0** | PostgreSQL CLI client |
| 18 | lnav | 7,868 | 0 | **7,868** | **7.7** | Advanced log navigator |
| 19 | redis-tools | 5,837 | 956 | **6,793** | **6.6** | Redis CLI + benchmark |
| 5 | haproxy | 4,223 | 792 | **5,015** | **4.9** | TCP/HTTP load balancer |
| 23 | apparmor-utils | 377 | 3,189 | **3,566** | **3.5** | AppArmor profile management |
| 9 | sg3-utils | 2,802 | 319 | **3,121** | **3.0** | SCSI device utilities |
| 31 | parallel | 2,894 | 0 | **2,894** | **2.8** | Parallel job execution |
| 34 | sysbench | 353 | 2,340 | **2,693** | **2.6** | Multi-threaded benchmark |
| 22 | xorriso | 348 | 1,984 | **2,332** | **2.3** | ISO 9660 filesystem tool |
| 11 | smartmontools | 2,199 | 0 | **2,199** | **2.1** | SMART disk monitoring |
| 20 | fail2ban | 2,129 | 0 | **2,129** | **2.1** | Intrusion prevention |
| 10 | bird2 | 1,553 | 637 | **2,190** | **2.1** | Routing daemon (BGP/OSPF) |
| 28 | tcpreplay | 1,962 | 94 | **2,056** | **2.0** | Pcap replay/editing |
| 21 | lynis | 1,658 | 0 | **1,658** | **1.6** | Security audit scanner |
| 27 | arp-scan | 1,567 | 0 | **1,567** | **1.5** | ARP network scanner |
| 26 | blktrace | 1,072 | 0 | **1,072** | **1.0** | Block I/O tracing |
| 24 | aide (+common) | 293 | 750 | **1,043** | **1.0** | File integrity checker |
| 25 | auditd | 745 | 277 | **1,022** | **1.0** | Kernel audit daemon |
| 33 | clustershell | 95 | 631 | **726** | **0.7** | Parallel cluster commands |
| 35 | gddrescue | 435 | 0 | **435** | **0.4** | Data recovery tool |
| 13 | iperf3 | 86 | 308 | **394** | **0.4** | Bandwidth measurement |
| 12 | apache2-utils | 444 | 568 | **1,012** | **1.0** | HTTP bench/password tools |
| 31 | parallel | 2,894 | 0 | **2,894** | **2.8** | Parallel job execution |
| 32 | watchdog | 229 | 0 | **229** | **0.2** | HW/SW watchdog daemon |
| 29 | fping | 93 | 133 | **226** | **0.2** | Fast parallel ping |
| 30 | iputils-arping | 50 | 133 | **183** | **0.2** | ARP ping utility |

---

## RED FLAGS AND RECOMMENDATIONS

### CRITICAL: tshark at 124 MB
libwireshark16 is 111 MB installed. This is the Wireshark dissection engine with support for
thousands of protocols. There is no lightweight alternative in Debian. Consider whether `tcpdump`
(already in base?) plus `tshark` on-demand (container/download) is sufficient.

### WARNING: stress-ng pulls Mesa/X11 at ~6.5 MB + libipsec-mb1 at 12.5 MB
The EGL/Mesa/X11 chain is for GPU stress tests. libipsec-mb1 is for crypto stress tests.
These are compiled-in features of the Debian package. Total ~29 MB is high.

### WARNING: fio pulls GlusterFS client libs at ~13.6 MB
The libgfapi0 chain (4 GlusterFS libraries) is for GlusterFS I/O benchmarking, compiled into
the Debian fio package. If you don't need gluster benchmarks, this is dead weight.

### WARNING: openvswitch at ~27 MB
This is inherently large (kernel datapath + userspace switch + Python management).
The libunbound8 DNS resolver adds ~1.7 MB.

### Go binaries (buildah, skopeo, prometheus-node-exporter) are self-contained
No transitive dep surprises, but their static binaries are large by nature (14-20 MB each).

### Best value packages (< 3 MB, clean deps):
smartmontools (2.1 MB), iperf3 (0.4 MB), apache2-utils (1.0 MB), lynis (1.6 MB),
fail2ban (2.1 MB), auditd (1.0 MB), aide (1.0 MB), bird2 (2.1 MB), sg3-utils (3.0 MB),
blktrace (1.0 MB), arp-scan (1.5 MB), tcpreplay (2.0 MB), gddrescue (0.4 MB),
watchdog (0.2 MB), fping (0.2 MB), iputils-arping (0.2 MB), clustershell (0.7 MB)

---

## GRAND TOTAL IF ALL PACKAGES INSTALLED

**Group A (28 packages):** ~380 MB installed
**Group B (7 packages):** ~7.9 MB installed
**Combined:** ~388 MB installed

**Without tshark:** ~264 MB installed
**Without tshark + stress-ng:** ~235 MB installed
**Without tshark + stress-ng + fio:** ~219 MB installed
