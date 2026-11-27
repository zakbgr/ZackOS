#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Fedora 44 CI: the shipped modules and the CLI against the REAL Fedora kitty, zsh and fastfetch,
# real dnf5 (read-only commands) and a real unprivileged user. Runs only in a fedora:44 container.
set -u
# shellcheck source=tests/dnf5/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
ci_guard

echo "== tooling and packages (real Fedora 44 repositories)"
dnf5 --version | head -2
dnf5 -y install kitty zsh fastfetch jq util-linux >/dev/null 2>&1 || {
    record "R0 install kitty zsh fastfetch from Fedora" FAIL
    finish "Fedora 44 real packages"
}
record "R0 install kitty zsh fastfetch from Fedora" PASS "$(rpm -q kitty zsh fastfetch | tr '\n' ' ')"

echo
echo "== R1 origin classification against real repository IDs"
for p in kitty zsh fastfetch; do
    o="$( (source "${REPO_ROOT}/lib/dnf.sh"; dnf_installed_origin "${p}") )"
    c="$( (source "${REPO_ROOT}/lib/dnf.sh"; dnf_origin_class "${o}") )"
    echo "   ${p}: from_repo='${o}' class='${c}'"
    if [[ "${c}" == "fedora" ]]; then record "R1 ${p} origin is fedora" PASS "(${o})"; else record "R1 ${p} origin is fedora" FAIL "(from_repo='${o}': extend dnf_origin_class or fix the query tag)"; fi
done

echo
echo "== R2 Dolphin footprint on a GNOME-less container (informational, nothing installed)"
dnf5 -y --assumeno install dolphin 2>&1 | tail -15 | sed 's/^/   | /'
record "R2 dolphin dependency footprint printed" PASS "(informational: see log)"

echo
echo "== R3 modules and CLI as an unprivileged user"
id zuser >/dev/null 2>&1 || useradd -m zuser
rm -rf /home/zuser/zackos
cp -a "${REPO_ROOT}" /home/zuser/zackos
chown -R zuser:zuser /home/zuser
as_user() { runuser -u zuser -- env HOME=/home/zuser ZACKOS_STATE_DIR=/home/zuser/.local/state/zackos NO_COLOR=1 "$@"; }
Z=/home/zuser/zackos/bin/zackos

out="$(as_user bash "${Z}" doctor 2>&1)"
printf '%s\n' "${out//$'\n'/$'\n'   | }" | sed '1s/^/   | /'
if grep -q 'nothing was changed' <<<"${out}" && grep -q 'COPR operations: locked' <<<"${out}"; then record "R3a doctor against real dnf5 (read-only)" PASS; else record "R3a doctor against real dnf5 (read-only)" FAIL; fi
if grep -qE '^(kitty|zsh|fastfetch) +state=fedora +action=ok' <<<"${out}"; then record "R3b doctor classifies the three packages as fedora/ok" PASS; else record "R3b doctor classifies the three packages as fedora/ok" FAIL; fi

as_user bash "${Z}" packages install >/dev/null 2>&1; rc=$?
if ((rc == 0)); then record "R3c packages install dry-run is harmless" PASS; else record "R3c packages install dry-run is harmless" FAIL "rc=${rc}"; fi
as_user bash "${Z}" repo enable >/dev/null 2>&1; rc=$?
if ((rc == 5)) && ! ls /etc/yum.repos.d/*copr* >/dev/null 2>&1; then record "R3d repo enable is locked and creates no repo file" PASS; else record "R3d repo enable is locked and creates no repo file" FAIL "rc=${rc}"; fi

as_user bash "${Z}" install kitty zsh fastfetch --apply >/dev/null 2>&1; rc=$?
if ((rc == 0)); then record "R3e install --apply into the user's HOME" PASS; else record "R3e install --apply into the user's HOME" FAIL "rc=${rc}"; fi

echo
echo "== R4 config validation with the real programs"
cfg=/home/zuser/.config
out="$(as_user timeout 60 fastfetch -c "${cfg}/fastfetch/config.jsonc" --pipe 2>&1)"; rc=$?
if ((rc == 0)) && [[ -n "${out}" ]]; then record "R4a fastfetch accepts the ZackOS config" PASS; else record "R4a fastfetch accepts the ZackOS config" FAIL "rc=${rc}: ${out%%$'\n'*}"; fi
printf '{ "modules": [ \n' >/tmp/broken.jsonc
as_user timeout 60 fastfetch -c /tmp/broken.jsonc --pipe >/dev/null 2>&1; rc=$?
if ((rc != 0)); then record "R4b control: fastfetch rejects a broken config" PASS; else record "R4b control: fastfetch rejects a broken config" FAIL "validation proves nothing"; fi

out="$(as_user timeout 60 kitty --debug-config 2>&1)"; rc=$?
echo "${out}" | head -5 | sed 's/^/   | /'
if ((rc != 0)); then
    record "R4c kitty parses the ZackOS config" SKIP "kitty --debug-config failed headless (rc=${rc}): ${out%%$'\n'*}"
elif grep -qiE 'ignoring|invalid|error' <<<"${out}"; then
    record "R4c kitty parses the ZackOS config" FAIL "$(grep -iE 'ignoring|invalid|error' <<<"${out}" | head -3)"
else
    record "R4c kitty parses the ZackOS config" PASS
fi

z=/home/zuser/.config/zackos/zsh
if as_user zsh -n "${z}/zackos.zsh" && as_user zsh -n "${z}/zackos-theme.zsh"; then record "R4d zsh syntax of both files" PASS; else record "R4d zsh syntax of both files" FAIL; fi
out="$(as_user env -i HOME=/home/zuser PATH="${PATH}" zsh -f -c "source ${z}/zackos.zsh; print -r -- \"\${ZACKOS_FG_ACCENT}\"" 2>&1)"
if [[ "${out}" == "38;2;0;217;255" ]]; then record "R4e zsh sources the file and sets the palette" PASS; else record "R4e zsh sources the file and sets the palette" FAIL "${out}"; fi
if [[ ! -e /home/zuser/.zshrc ]]; then record "R4f no .zshrc created" PASS; else record "R4f no .zshrc created" FAIL; fi
shell_before="$(getent passwd zuser | cut -d: -f7)"

echo
echo "== R5 rollback leaves nothing behind"
as_user bash "${Z}" rollback --apply >/dev/null 2>&1
as_user bash "${Z}" rollback --apply >/dev/null 2>&1; rc=$?
left="$(find /home/zuser/.config -mindepth 1 2>/dev/null | head -5)"
if ((rc == 0)) && [[ -z "${left}" ]]; then record "R5a rollback twice: clean and idempotent" PASS; else record "R5a rollback twice: clean and idempotent" FAIL "rc=${rc} left: ${left}"; fi
if [[ "$(getent passwd zuser | cut -d: -f7)" == "${shell_before}" ]]; then record "R5b login shell unchanged" PASS; else record "R5b login shell unchanged" FAIL; fi

echo
echo "== R6 the full local suite on Fedora 44 (bash/python versions differ from CI Ubuntu)"
dnf5 -y install python3 git ShellCheck >/dev/null 2>&1
if (cd /home/zuser/zackos && as_user bash tests/run.sh >/tmp/suite.out 2>&1); then record "R6 tests/run.sh on Fedora 44" PASS "$(grep -c passed /tmp/suite.out) shell suites"; else record "R6 tests/run.sh on Fedora 44" FAIL; tail -25 /tmp/suite.out; fi

finish "Fedora 44 real packages and CLI"
