#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/shell/harness.sh
source "${HERE}/harness.sh"
# shellcheck source=lib/preflight.sh
source "${HERE}/../../lib/preflight.sh"

make_tmp
export NO_COLOR=1
export ZACKOS_ROOT="${T_TMP}/root"
mkdir -p "${ZACKOS_ROOT}/etc"

assert_rc 0 "not root passes" env ZACKOS_TEST_EUID=1000 bash -c "source '${HERE}/../../lib/preflight.sh'; preflight_not_root"
assert_rc 2 "root fails" env ZACKOS_TEST_EUID=0 bash -c "source '${HERE}/../../lib/preflight.sh'; preflight_not_root"

printf 'ID=fedora\nVERSION_ID=44\n' >"${ZACKOS_ROOT}/etc/os-release"
assert_rc 0 "fedora any version" preflight_fedora
assert_rc 0 "fedora 44" preflight_fedora 44
assert_rc 2 "fedora 43 wanted" preflight_fedora 43

printf 'ID=debian\nVERSION_ID=12\n' >"${ZACKOS_ROOT}/etc/os-release"
assert_rc 2 "non-fedora fails" preflight_fedora

assert_rc 0 "arch matches" preflight_arch "$(uname -m)"
assert_rc 2 "arch mismatch" preflight_arch not-an-arch

assert_rc 0 "commands present" preflight_commands bash ls
assert_rc 2 "command missing" preflight_commands bash definitely-not-a-command-xyz
msg="$(preflight_commands definitely-not-a-command-xyz 2>&1 || true)"
assert_contains "${msg}" "definitely-not-a-command-xyz" "missing command is named"

assert_rc 0 "home writable" env HOME="${T_TMP}" bash -c "source '${HERE}/../../lib/preflight.sh'; preflight_home_writable"
assert_rc 2 "home unset" env -u HOME bash -c "source '${HERE}/../../lib/preflight.sh'; preflight_home_writable"

t_finish
