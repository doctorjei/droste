# Building

```bash
scripts/drostify build thread          # build + test thread
scripts/drostify build yarn            # build + test yarn
scripts/drostify test fabric           # test an existing fabric image
scripts/drostify test all              # smoke test all tiers
scripts/drostify build all             # build all tiers (requires --force if images exist)
scripts/drostify all jacquard          # build prerequisites + jacquard
```

Requires KVM and Packer. Each tier auto-builds its prerequisites if missing.

## Default Credentials

| Field | Value |
|-------|-------|
| Username | `droste` |
| Password | `droste` |
| UID/GID | 1000 |
| Sudo | passwordless (NOPASSWD) |
| SSH | key + password auth enabled |

**These images are for isolated lab/test environments only.** Change the
password or disable password auth before exposing to any untrusted network.

## Testing

**SSH smoke tests** run after boot, verifying the current tier's packages are present:

```bash
scripts/ssh-smoke-test.sh --port 2222 --ssh-key KEY checks/thread.checks
```

Check files use tab-separated format: `description<TAB>command[<TAB>ssh-only]`

**Guest regression tests** run inside packer during the build, verifying that all *previous* tier packages survived the current tier's provisioning. This catches accidental package removal early — before the image is finalized.

## Image Layout

```
checks/              Check definition files (one per tier, tab-separated)
scripts/             Build, boot, and test scripts
ansible/             Ansible playbooks (one per tier)
packer/              Packer HCL configs (one per tier)
output-droste-*/     Built QCOW2 images (gitignored)
```
