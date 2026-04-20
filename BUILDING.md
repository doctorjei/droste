# Building

Droste OCI images are built with the `drostify` script. Three lines: app
(process containers), system (kento-bootable), and VM (kento VM-bootable).

```bash
scripts/drostify [COMMAND] [IMAGE] [OPTIONS]
```

Tier names are auto-detected — `drostify build fiber` builds the process
container, `drostify build thread` builds its system container sibling.

## OCI Builds

Requires Podman. All tiers, including seed, build from Containerfiles.

### Building seed

Seed inherits from [tenkei](https://github.com/doctorjei/tenkei)'s
`canopy` OCI image (pinned by semver in the Containerfile) and layers
on the droste user, sysctl forwarding, locales, and a restore list for
a handful of packages canopy strips that droste-seed still wants.

```bash
drostify build seed
```

No root or qemu-nbd is required — `podman build` is sufficient.

### Building tiers

All other OCI tiers build via Containerfiles the same way:

```bash
drostify build fiber               # build fiber (process container)
drostify build thread              # build thread (kento-bootable)
drostify build sheet               # builds fiber first if missing
drostify build app-all             # all process containers
drostify build sys-all             # all system containers
drostify build vm-all              # all VM-bootable containers
drostify build all                 # all OCI tiers (app + sys + vm)
drostify build sheet --force       # rebuild sheet + all downstream
drostify build sheet --force-tier  # rebuild only sheet
```

### OCI Testing

```bash
drostify test fiber                # test fiber
drostify test all                  # test all OCI tiers
```

### VM-bootable OCI images

The VM tier line adds kernel files (`/boot/vmlinuz` and `/boot/initramfs.img`,
copied from tenkei's `tenkei-kernel` OCI image via a multi-stage
`COPY --from=`), VM-specific packages (qemu-guest-agent, watchdog, libvirt,
nested virt tools, etc.), kernel module configs, password, and DHCP config
on top of each system image, enabling boot via kento VM mode (QEMU + virtiofs).

```bash
drostify build root                # build VM-bootable seed
drostify build vm-all              # build all VM tiers
```

## Options

| Flag | Effect |
|------|--------|
| `--force` | Rebuild named tier(s) and all downstream dependents |
| `--force-tier` | Rebuild only the named tier(s), without cascading downstream |
| `--deps` | Also rebuild ancestor dependencies (combine with `--force` or `--force-tier`) |
| `--verbose` | Show full build output (builds are quiet by default) |
| `--debug` | Alias for `--verbose` |

Default behavior (no flags) skips tiers whose images already exist.

`--force` cascades by default: rebuilding a tier invalidates its downstream
dependents, so they are included in the forced set. Use `--force-tier` to
force only the named tier(s) without cascading. Add `--deps` to either to
also force ancestor dependencies.

Examples:

```bash
drostify build sheet --force              # rebuild sheet + all downstream
drostify build sheet --force-tier         # rebuild only sheet
drostify build sys-all --force --deps     # rebuild sys tiers + app ancestors + downstream
drostify build sys-all --force-tier --deps  # rebuild sys tiers + app ancestors (no downstream)
drostify build all --force                # rebuild everything
```

## Credentials

OCI images have a `droste` user (UID 1000) with passwordless sudo. No
login password is set on app or system tiers. VM tiers have password
`droste` with sudo access for serial console login.

## Testing

### Running tests

Tests run containers and verify packages via check files:

```bash
drostify test fiber                # test fiber process container
drostify test thread               # test thread system container
drostify test all                  # test all OCI tiers
```

### Check files

Check files live in `checks/` (one per tier). Each line is either a
directive, a section header, or a test:

```
@quiet seed.checks              ← include another check file (quiet mode)
@stop                           ← everything below is local-only

# Section header                ← printed as a label during test output
description<TAB>command         ← a test (tab-separated)
```

**Test format:** `description<TAB>command`. The command runs inside the
container; exit 0 = pass, non-zero = fail.

**Directives:**

- `@quiet <file>` — Include checks from another file (resolved relative
  to `checks/`). Quiet checks run silently; only failures are reported.
  Tiers use this to inherit all ancestor checks without noisy output.
  System tiers include checks from their app counterpart and all lower
  app tiers (e.g., `fabric.checks` includes `seed`, `lint`, `fiber`,
  `thread`, `sheet`, `yarn`, and `page` checks). This is cross-line
  verification by design — fabric has the same packages as yarn
  (installed independently), and the quiet checks catch any divergence.

- `@stop` — Marks the end of inheritable checks. Lines after `@stop`
  are local to this tier and not included by any `@quiet` directive.
  Use this for negative tests (e.g., "package X should NOT be installed")
  that only make sense for this specific tier.

**Section headers:** Lines starting with `# ` (hash + space) are printed
as labels during verbose test output. Blank lines and lines starting
with `@` are skipped.

## Image Layout

```
checks/              Check files (one per tier, tab-separated)
scripts/             Build and test scripts (drostify, ssh-smoke-test.sh)
containers/          OCI Containerfiles (one dir per tier)
  droste-seed/       Seed Containerfile + canopy-restore.txt
  droste-fiber/      Fiber Containerfile (app)
  droste-thread/     Thread Containerfile (system)
  droste-hair/       Hair Containerfile (VM)
  ...                (one directory per OCI tier)
oci/                 OCI build support files
  seed-oci-exclude.txt  Packages stripped from seed (reinstalled in system tiers)
```

VM tiers pull `/boot/vmlinuz` and `/boot/initramfs.img` from tenkei's
`tenkei-kernel` OCI image via multi-stage `COPY --from=` — no kernel
files are checked into droste.
