#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Shared helpers for the Fedora 44 CI scenarios. These scripts run ONLY inside a disposable
# fedora:44 container as root. They refuse to run anywhere else, because they rewrite the
# repository configuration and install/remove packages.

# shellcheck disable=SC2034
REPO_ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULTS=()
FAILED=0

ci_guard() {
    if [[ "${ZACKOS_CI_CONTAINER:-}" != "1" ]]; then
        echo "refusing to run: set ZACKOS_CI_CONTAINER=1 (only inside a disposable fedora:44 container)" >&2
        exit 64
    fi
    if [[ ! -e /.dockerenv && ! -e /run/.containerenv ]]; then
        echo "refusing to run: not inside a container" >&2
        exit 64
    fi
    if ! grep -q '^VERSION_ID=44$' /etc/os-release; then
        echo "refusing to run: not Fedora 44" >&2
        exit 64
    fi
    if [[ "$(id -u)" != "0" ]]; then
        echo "refusing to run: expected root inside the container" >&2
        exit 64
    fi
}

# record <scenario> <PASS|FAIL|SKIP> [detail]
record() {
    RESULTS+=("$1|$2|${3:-}")
    printf 'RESULT %-46s %s %s\n' "$1" "$2" "${3:-}"
    [[ "$2" == "FAIL" ]] && FAILED=1
    return 0
}

# check <scenario> <command...>: PASS if the command succeeds.
check() {
    local name="$1"
    shift
    if "$@" >/tmp/check.out 2>&1; then
        record "${name}" PASS
    else
        record "${name}" FAIL "(see log above)"
        sed 's/^/    | /' /tmp/check.out
    fi
}

finish() {
    local r summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
    {
        echo "### $1"
        echo
        echo "| Scenario | Result | Detail |"
        echo "|---|---|---|"
        for r in "${RESULTS[@]}"; do IFS='|' read -r a b c <<<"${r}"; echo "| ${a} | ${b} | ${c} |"; done
    } >>"${summary}"
    echo
    echo "== $1: $(printf '%s\n' "${RESULTS[@]}" | grep -c '|PASS|') pass, $(printf '%s\n' "${RESULTS[@]}" | grep -c '|FAIL|') fail, $(printf '%s\n' "${RESULTS[@]}" | grep -c '|SKIP|') skip"
    exit "${FAILED}"
}
