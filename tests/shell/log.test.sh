#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -u
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/shell/harness.sh
source "${HERE}/harness.sh"
# shellcheck source=lib/log.sh
source "${HERE}/../../lib/log.sh"

make_tmp
export ZACKOS_STATE_DIR="${T_TMP}/state"
export NO_COLOR=1

# plain output goes to stderr, with level
out="$(log_info "hello" 2>&1 >/dev/null)"
assert_eq "[INFO] hello" "${out}" "log_info format"
out="$(log_error "bad" 2>&1 >/dev/null)"
assert_eq "[ERROR] bad" "${out}" "log_error format"
out="$(log_info "x" 2>/dev/null)"
assert_eq "" "${out}" "stdout stays empty"

# log_init creates a file and records lines (only when applying)
ZACKOS_APPLY=1
log_init testcmd
assert_file "${ZACKOS_LOG_FILE}" "log file created"
log_warn "careful" 2>/dev/null
assert_contains "$(cat "${ZACKOS_LOG_FILE}")" "[WARN] careful" "log file content"
assert_contains "${ZACKOS_LOG_FILE}" "${ZACKOS_STATE_DIR}/logs/" "log file location"

# dry-run (the default): no log file, zackos_run does not execute
ZACKOS_APPLY=0
ZACKOS_LOG_FILE=""
ZACKOS_DRY_RUN=1
log_init dry
assert_eq "" "${ZACKOS_LOG_FILE}" "no log file in dry-run"
marker="${T_TMP}/marker"
zackos_run touch "${marker}" 2>/dev/null
assert_no_path "${marker}" "dry-run must not execute"
ZACKOS_DRY_RUN=0
zackos_run touch "${marker}" 2>/dev/null
assert_no_path "${marker}" "dry-run is the default: nothing runs without ZACKOS_APPLY=1"
ZACKOS_APPLY=1
zackos_run touch "${marker}" 2>/dev/null
assert_file "${marker}" "zackos_run executes with ZACKOS_APPLY=1"
rm -f -- "${marker}"
ZACKOS_DRY_RUN=1
zackos_run touch "${marker}" 2>/dev/null
assert_no_path "${marker}" "ZACKOS_DRY_RUN=1 beats ZACKOS_APPLY=1"
ZACKOS_DRY_RUN=0
ZACKOS_APPLY=0

# exit code constants
assert_eq "5" "${ZACKOS_EXIT_LOCKED}" "locked exit code"

# die exits with the given code
assert_rc 3 "die exit code" bash -c "source '${HERE}/../../lib/log.sh'; die 3 'boom'"

# color output uses truecolor escape when forced via a pty-less check: NO_COLOR wins
out="$(NO_COLOR=1 log_info "c" 2>&1 >/dev/null)"
assert_eq "[INFO] c" "${out}" "NO_COLOR respected"

t_finish
