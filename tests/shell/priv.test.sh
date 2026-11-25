#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/shell/harness.sh
source "${HERE}/harness.sh"

make_tmp
use_fakebin
export NO_COLOR=1
export ZACKOS_STATE_DIR="${T_TMP}/state"
export ZACKOS_TEST_EUID=1000
LIB="${HERE}/../../lib/priv.sh"

# run_step <answers-file-content> <args...>: run priv_step in a fresh shell with scripted answers
run_step() {
    local answers="$1"
    shift
    printf '%b' "${answers}" >"${T_TMP}/answers"
    bash -c "source '${LIB}'; priv_step \"\$@\"" _ "$@" 2>&1
}

journal="${ZACKOS_STATE_DIR}/priv-journal.tsv"

# ---- dry-run is the default: nothing runs, nothing is written
out="$(run_step "yes\n" "Install thing" "undo it" dnf5 install thing)"
assert_contains "${out}" "sudo dnf5 install thing" "dry-run shows the command"
assert_contains "${out}" "undo it" "dry-run shows the undo"
assert_contains "${out}" "would: run with sudo" "dry-run says it would run"
assert_eq "" "$(cat "${FAKE_LOG}")" "dry-run called nothing"
assert_no_path "${journal}" "dry-run writes no journal"

# ---- apply + exact "yes" runs the command through sudo
export ZACKOS_APPLY=1 ZACKOS_PRIV_INPUT="${T_TMP}/answers"
out="$(run_step "yes\n" "Install thing" "undo it" dnf5 install thing)"
assert_contains "${out}" "done: Install thing" "confirmed step ran"
assert_eq "sudo dnf5 install thing" "$(cat "${FAKE_LOG}")" "exactly one sudo call with exact argv"
assert_file "${journal}" "journal written"
assert_contains "$(cat "${journal}")" $'Install thing\tsudo dnf5 install thing\tundo it\tok' "journal records description, command, undo, result"

# ---- anything but "yes" declines (rc 3), nothing runs
: >"${FAKE_LOG}"
for ans in "y\n" "YES\n" "no\n" "\n" "yes please\n" ""; do
    rc=0
    run_step "${ans}" "Install thing" "undo" dnf5 install thing >/dev/null || rc=$?
    assert_eq "3" "${rc}" "declined for answer '${ans}'"
done
assert_eq "" "$(cat "${FAKE_LOG}")" "declined steps ran nothing"
assert_contains "$(cat "${journal}")" "declined" "declines are journaled"

# ---- no global yes
rc=0
ZACKOS_ASSUME_YES=1 run_step "no\n" "Install thing" "undo" dnf5 install thing >/dev/null || rc=$?
assert_eq "3" "${rc}" "ZACKOS_ASSUME_YES is ignored"
rc=0
run_step "no\n" a b true --yes -y >/dev/null || rc=$?
assert_eq "3" "${rc}" "a -y flag in the command does not skip confirmation"

# ---- two steps need two separate confirmations
: >"${FAKE_LOG}"
rm -f "${journal}"
printf 'yes\nno\n' >"${T_TMP}/answers"
bash -c "source '${LIB}'; priv_step one u1 dnf5 install one; r1=\$?; priv_step two u2 dnf5 install two; r2=\$?; echo \"r1=\$r1 r2=\$r2\"" 2>&1 | tail -1 >"${T_TMP}/res"
assert_eq "r1=0 r2=3" "$(cat "${T_TMP}/res")" "first confirmed, second declined independently"
assert_eq "sudo dnf5 install one" "$(cat "${FAKE_LOG}")" "only the confirmed step ran"

# ---- arguments with spaces and metacharacters stay single arguments
: >"${FAKE_LOG}"
run_step "yes\n" "odd" "undo" echo 'a b;c $(x)' >/dev/null
assert_eq "sudo echo a b;c \$(x)" "$(cat "${FAKE_LOG}")" "arguments are passed through as given (not evaluated)"

# ---- refuses root
rc=0
ZACKOS_TEST_EUID=0 run_step "yes\n" "Install thing" "undo" dnf5 install thing >/dev/null || rc=$?
assert_eq "2" "${rc}" "root is refused"

# ---- failures are reported and journaled
rc=0
cat >"${T_TMP}/failing-sudo" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
chmod +x "${T_TMP}/failing-sudo"
rc=0
PATH="${T_TMP}/fail:${PATH}"
mkdir -p "${T_TMP}/fail" && cp "${T_TMP}/failing-sudo" "${T_TMP}/fail/sudo"
run_step "yes\n" "will fail" "undo" true >/dev/null || rc=$?
assert_eq "7" "${rc}" "sudo exit code is returned"
assert_contains "$(cat "${journal}")" "failed:7" "failure journaled"

# ---- tabs/newlines cannot corrupt the journal format
run_step "yes\n" $'desc\twith\ttabs' $'undo\nline' true >/dev/null || true
assert_eq "5" "$(tail -n1 "${journal}" | awk -F'\t' '{print NF}')" "journal rows keep 5 fields"

# ---- missing command is a usage error
assert_rc 2 "no command" bash -c "export ZACKOS_APPLY=1; source '${LIB}'; priv_step a b"

t_finish
