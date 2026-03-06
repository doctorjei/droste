#!/usr/bin/env bash
# Run regression checks locally inside a packer build guest.
#
# Reads one or more check definition files and executes each check
# via eval. Silent on pass — only prints failures. Skips checks
# marked as ssh-only. Exits non-zero on any failure.
#
# Usage:
#   sudo /tmp/guest-regression-test.sh /tmp/checks/thread.checks [...]
set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "Usage: $(basename "$0") CHECKFILE [CHECKFILE ...]" >&2
    exit 1
fi

PASS=0
FAIL=0
ERRORS=()

for checkfile in "$@"; do
    if [[ ! -f "$checkfile" ]]; then
        echo "FAIL: check file not found: $checkfile" >&2
        exit 1
    fi

    tier=$(basename "$checkfile" .checks)

    tier_pass=0
    tier_fail=0

    while IFS= read -r line; do
        # Skip empty lines and section headers
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^#\  ]] && continue

        # Parse: description<TAB>command [<TAB>ssh-only]
        IFS=$'\t' read -r desc cmd flag <<< "$line"

        # Skip ssh-only checks
        [[ "$flag" == "ssh-only" ]] && continue

        if eval "$cmd" &>/dev/null; then
            PASS=$((PASS + 1))
            tier_pass=$((tier_pass + 1))
        else
            echo "FAIL [$tier]: $desc"
            ERRORS+=("[$tier] $desc")
            FAIL=$((FAIL + 1))
            tier_fail=$((tier_fail + 1))
        fi
    done < "$checkfile"

    if [[ $tier_fail -eq 0 ]]; then
        echo "droste-${tier} guest checks passed. (${tier_pass}/${tier_pass})"
    fi
done

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "Guest regression: ${PASS} passed, ${FAIL} FAILED"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi

echo "Guest regression: ${PASS} passed, 0 failed"
