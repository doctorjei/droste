# Building

```bash
scripts/build.sh thread          # build + test thread
scripts/build.sh yarn build      # build yarn (no test)
scripts/build.sh fabric test     # test an existing fabric image
scripts/build.sh all test        # smoke test all tiers
scripts/build.sh all build       # build all tiers (requires --force if images exist)
```

Requires KVM and Packer. Each tier auto-builds its prerequisites if missing.

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
