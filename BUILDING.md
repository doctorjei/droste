# Building

Droste OCI images are built with the `drostify` script. Three lines: app
(process containers), system (kento-bootable), and VM (kento VM-bootable).

```bash
scripts/drostify [COMMAND] [IMAGE] [OPTIONS]
```

Tier names are auto-detected — `drostify build fiber` builds the process
container, `drostify build thread` builds its system container sibling.

## OCI Builds

Requires Podman. The seed base image must be built first (separately).

### Building seed

The seed is built by a standalone script that extracts the genericcloud
qcow2 image, strips kernel/boot/init packages, creates the droste user,
and imports the result into Podman. Requires root and nbd kernel module.

```bash
sudo containers/droste-seed/build-seed.sh
```

### Building tiers

Once seed exists, all other OCI tiers build via Containerfiles:

```bash
drostify build fiber               # build fiber (process container)
drostify build thread              # build thread (kento-bootable)
drostify build sheet               # builds fiber first if missing
drostify build app-all             # all process containers
drostify build sys-all             # all system containers
drostify build vm-all              # all VM-bootable containers
drostify build all                 # all OCI tiers (app + sys + vm)
drostify build sheet --force-cascade  # rebuild sheet + all downstream
```

### OCI Testing

```bash
drostify test fiber                # test fiber
drostify test all                  # test all OCI tiers
```

### VM-bootable OCI images

The VM tier line adds kernel files (`/boot/vmlinuz` and `/boot/initramfs.img`)
on top of each system image, plus password and DHCP config, enabling boot
via kento VM mode (QEMU + virtiofs).

```bash
drostify build root                # build VM-bootable seed
drostify build vm-all              # build all VM tiers
```

## Build-All

Build all OCI images in one command:

```bash
drostify build-all                 # build all OCI images
drostify build-all --force         # rebuild everything
```

## Options

| Flag | Effect |
|------|--------|
| `--force` | Rebuild named tier(s) even if images already exist |
| `--force-cascade` | Rebuild named tier(s) and all downstream dependents |
| `--verbose` | Show full build output (builds are quiet by default) |

Default behavior (no flags) skips tiers whose images already exist.

## Credentials

OCI images have a `droste` user (UID 1000) with passwordless sudo. No
login password is set on app or system tiers. VM tiers have password
`droste` with sudo access for serial console login.

## Testing

### OCI tests

OCI tests run containers and verify packages via check files:

```bash
drostify test fiber                # test fiber process container
drostify test thread               # test thread system container
drostify test all                  # test all OCI tiers
```

### Check files

Check files live in `checks/` (one per tier, tab-separated format):

```
description<TAB>command
```

Check files use `@quiet <file>` directives to include parent tier
checks (run silently, failures still reported). Use `@stop` to mark a
section boundary — checks after `@stop` are not included by child tiers.

## Image Layout

```
checks/              Check files (one per tier, tab-separated)
scripts/             Build and test scripts (drostify, ssh-smoke-test.sh)
containers/          OCI Containerfiles (one dir per tier)
  droste-seed/       Seed build script + target package list
  droste-fiber/      Fiber Containerfile (app)
  droste-thread/     Thread Containerfile (system)
  droste-hair/       Hair Containerfile (VM)
  ...                (one directory per OCI tier)
oci/                 OCI build support files
  seed-oci-exclude.txt  Packages stripped from seed (reinstalled in system tiers)
  vmlinuz            Kernel for VM tiers
  initramfs.img      Initramfs for VM tiers
```
