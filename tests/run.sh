#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Run every test and static check. Safe to run anywhere: tests use temporary directories
# and never touch your real $HOME or system.
#   bash tests/run.sh
set -u
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." || exit 1

failed=0
step() { printf '\n== %s\n' "$*"; }

step "generated theme files are up to date"
python3 -I scripts/render-theme.py --check || failed=1

step "python unit tests"
python3 -I -m unittest discover -s tests -q || failed=1

for t in tests/shell/*.test.sh; do
    step "shell: ${t}"
    bash "${t}" || failed=1
done

if command -v shellcheck >/dev/null 2>&1; then
    step "shellcheck"
    shellcheck -x lib/*.sh scripts/detect-env tests/run.sh tests/shell/*.sh || failed=1
else
    step "shellcheck (skipped: not installed)"
fi

echo
if [[ "${failed}" -eq 0 ]]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit "${failed}"
