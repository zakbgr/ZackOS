#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Minimal assertion helpers (no external test framework needed).

t_pass=0
t_fail=0

_t_ok() { t_pass=$((t_pass + 1)); }
_t_bad() {
    t_fail=$((t_fail + 1))
    printf '  FAIL: %s\n' "$*" >&2
}

assert_eq() { # expected actual message
    if [[ "$1" == "$2" ]]; then _t_ok; else _t_bad "${3:-assert_eq}: expected [$1] got [$2]"; fi
}
assert_contains() { # haystack needle message
    if [[ "$1" == *"$2"* ]]; then _t_ok; else _t_bad "${3:-assert_contains}: [$2] not found in [$1]"; fi
}
assert_rc() { # expected_rc message command...
    local want="$1" msg="$2" rc=0
    shift 2
    "$@" >/dev/null 2>&1 || rc=$?
    if [[ "${rc}" -eq "${want}" ]]; then _t_ok; else _t_bad "${msg}: expected rc ${want}, got ${rc}"; fi
}
assert_file() { if [[ -f "$1" ]]; then _t_ok; else _t_bad "${2:-missing file}: $1"; fi; }
assert_no_path() { if [[ ! -e "$1" && ! -L "$1" ]]; then _t_ok; else _t_bad "${2:-path should not exist}: $1"; fi; }
assert_link() { # path expected_target
    if [[ -L "$1" && "$(readlink -- "$1")" == "$2" ]]; then _t_ok; else _t_bad "symlink $1 -> $2 expected"; fi
}

# make_tmp: create a scratch dir under TMPDIR and clean it on exit.
make_tmp() {
    T_TMP="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf -- '${T_TMP}'" EXIT
}

t_finish() {
    printf '  %d passed, %d failed\n' "${t_pass}" "${t_fail}"
    [[ "${t_fail}" -eq 0 ]]
}
