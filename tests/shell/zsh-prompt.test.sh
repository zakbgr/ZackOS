#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# ZackOS Zsh prompt, tested with the real zsh and git in a scratch HOME. Never touches the
# real HOME, history or rc files.
set -u
cd "$(dirname -- "${BASH_SOURCE[0]}")/../.." || exit 1
# shellcheck source=tests/shell/harness.sh
source tests/shell/harness.sh

if ! command -v zsh >/dev/null 2>&1; then
    echo "  SKIP: zsh not installed"
    exit 0
fi
HAVE_GIT=0
command -v git >/dev/null 2>&1 && HAVE_GIT=1

make_tmp
ZDIR="$(pwd)/modules/zsh/files/.config/zackos/zsh"
export HOME="${T_TMP}/home"
mkdir -p "${HOME}"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# Root gets "#" by design; the expected symbol follows the user running the test.
SYM='❯'; ASYM='>'
if [[ "$(id -u)" -eq 0 ]]; then SYM='#'; ASYM='#'; fi

# render <dir> <exit-status> [extra env assignments...]: the expanded prompt, as zsh draws it.
render() {
    local dir="$1" rc="$2"
    shift 2
    env -i HOME="${HOME}" PATH="${PATH}" LANG=C.UTF-8 LC_ALL=C.UTF-8 COLUMNS=100 "$@" \
        zsh -f -i -c "source '${ZDIR}/zackos.zsh'; cd -- '${dir}'; _zackos_prompt_precmd; (exit ${rc}); print -r -- \"\${(%)PROMPT}\"" 2>&1
}
# plain: drop SGR sequences, leaving what the eye sees.
plain() { sed -e $'s/\x1b\\[[0-9;]*m//g'; }

assert_rc 0 "prompt.zsh syntax" zsh -n "${ZDIR}/prompt.zsh"
assert_rc 0 "zackos.zsh syntax" zsh -n "${ZDIR}/zackos.zsh"

# --- outside a repository -------------------------------------------------------------------
mkdir -p "${T_TMP}/plain/a/b"
out="$(render "${T_TMP}/plain" 0)"
assert_eq "${T_TMP}/plain ${SYM} " "$(plain <<<"${out}")" "outside a repo: directory and symbol only"
assert_contains "${out}" $'\e[38;2;0;217;255m' "directory uses the accent color"
assert_contains "${out}" $'\e[38;2;0;230;118m'"${SYM}" "success symbol is green"
bad="$(render "${T_TMP}/plain" 3)"
assert_eq "${T_TMP}/plain [3] ${SYM} " "$(plain <<<"${bad}")" "failure shows the exit code, not only a color"
assert_contains "${bad}" $'\e[38;2;255;82;82m[3] '"${SYM}" "failure symbol is red"
assert_eq "0" "$(grep -c $'38;2;0;230;118m'"${SYM}" <<<"${bad}")" "failure is not drawn in green"

# long path is shortened
deep="${T_TMP}/plain/a/b/c/d/e"
mkdir -p "${deep}"
assert_contains "$(plain <<<"$(render "${deep}" 0)")" "…/d/e" "deep path shortened to its last two components"

# non-UTF-8 locale falls back to ASCII
asc="$(env -i HOME="${HOME}" PATH="${PATH}" LANG=C LC_ALL=C COLUMNS=100 zsh -f -i -c "source '${ZDIR}/zackos.zsh'; cd '${T_TMP}/plain'; _zackos_prompt_precmd; print -r -- \"\${(%)PROMPT}\"" 2>&1 | sed -e $'s/\x1b\\[[0-9;]*m//g')"
assert_eq "${T_TMP}/plain ${ASYM} " "${asc}" "C locale uses an ASCII symbol"

# --- width safety: every escape is inside %{ %} ---------------------------------------------
raw="$(env -i HOME="${HOME}" PATH="${PATH}" LC_ALL=C.UTF-8 COLUMNS=100 zsh -f -i -c "source '${ZDIR}/zackos.zsh'; print -r -- \"\${PROMPT}\"" 2>&1)"
# shellcheck disable=SC2001
stripped="$(sed -e $'s/%{\x1b\\[[0-9;]*m%}//g' <<<"${raw}")"
assert_eq "0" "$(grep -c $'\x1b' <<<"${stripped}")" "no escape sequence outside %{ %}"

# --- source hygiene ---------------------------------------------------------------------------
src_out="$(env -i HOME="${HOME}" PATH="${PATH}" LC_ALL=C.UTF-8 zsh -f -i -c "source '${ZDIR}/zackos.zsh'" 2>&1)"
assert_eq "" "${src_out}" "sourcing prints nothing"
cnt="$(env -i HOME="${HOME}" PATH="${PATH}" LC_ALL=C.UTF-8 zsh -f -i -c "source '${ZDIR}/zackos.zsh'; source '${ZDIR}/zackos.zsh'; local -a m=(\${(M)precmd_functions:#_zackos_prompt_precmd}); print \${#m}" 2>&1)"
assert_eq "1" "${cnt}" "sourcing twice registers the hook once"
assert_eq "|0" "$(env -i HOME="${HOME}" PATH="${PATH}" zsh -f -c "source '${ZDIR}/zackos.zsh'; print -r -- \"\${PROMPT-}|\${+precmd_functions}\"" 2>&1 | sed 's/^\(.*\)|.*/\1|0/')" "non-interactive shell: prompt untouched"
for rc in .zshrc .zprofile .zshenv .zlogin; do assert_no_path "${HOME}/${rc}" "no ${rc} created"; done

# user prompt kept with ZACKOS_PROMPT=0
keep="$(env -i HOME="${HOME}" PATH="${PATH}" ZACKOS_PROMPT=0 zsh -f -i -c "PROMPT='mine> '; source '${ZDIR}/zackos.zsh'; print -r -- \"\${PROMPT}\"" 2>&1)"
assert_eq "mine> " "${keep}" "ZACKOS_PROMPT=0 keeps the user's prompt"
# without palette variables the user's prompt is kept
nopal="$(env -i HOME="${HOME}" PATH="${PATH}" zsh -f -i -c "PROMPT='mine> '; source '${ZDIR}/prompt.zsh'; print -r -- \"\${PROMPT}\"" 2>&1)"
assert_eq "mine> " "${nopal}" "no palette variables: user's prompt untouched"

# history and shell options are not changed by the prompt file
hist="$(env -i HOME="${HOME}" PATH="${PATH}" HISTFILE="${T_TMP}/myhist" HISTSIZE=77 zsh -f -i -c "setopt NO_SHARE_HISTORY; source '${ZDIR}/prompt.zsh'; source '${ZDIR}/zackos-theme.zsh'; source '${ZDIR}/prompt.zsh'; print -r -- \"\${HISTFILE}|\${HISTSIZE}|\${options[sharehistory]}\"" 2>&1)"
assert_eq "${T_TMP}/myhist|77|off" "${hist}" "prompt.zsh leaves HISTFILE, HISTSIZE and options alone"

if [[ "${HAVE_GIT}" -eq 1 ]]; then
    R="${T_TMP}/repo"
    git init -q -b main "${R}"
    git -C "${R}" commit -q --allow-empty -m init
    out="$(plain <<<"$(render "${R}" 0)")"
    assert_eq "${R} main ${SYM} " "${out}" "clean repo: branch only"

    # dirty: staged, modified, untracked
    printf 'a\n' >"${R}/a"; printf 'b\n' >"${R}/b"; printf 'c\n' >"${R}/c"
    git -C "${R}" add a b c && git -C "${R}" commit -q -m files
    printf 'a2\n' >>"${R}/a"; git -C "${R}" add a
    printf 'b2\n' >>"${R}/b"
    printf 'new\n' >"${R}/u"
    out="$(plain <<<"$(render "${R}" 0)")"
    assert_eq "${R} main +1 !1 ?1 ${SYM} " "${out}" "staged, modified and untracked counts"
    assert_contains "$(render "${R}" 0)" $'\e[38;2;255;179;0mmain' "dirty branch drawn in warning color"

    # works from a subdirectory
    mkdir -p "${R}/sub"
    assert_contains "$(plain <<<"$(render "${R}/sub" 0)")" "main +1 !1 ?1" "found from a subdirectory"

    # ahead / behind with a local remote
    git -C "${R}" checkout -q -- . 2>/dev/null; git -C "${R}" reset -q --hard; rm -f "${R}/u"
    git init -q --bare -b main "${T_TMP}/remote.git"
    git -C "${R}" remote add origin "${T_TMP}/remote.git"
    git -C "${R}" push -q -u origin main 2>/dev/null
    git -C "${R}" commit -q --allow-empty -m ahead1
    git -C "${R}" commit -q --allow-empty -m ahead2
    out="$(plain <<<"$(render "${R}" 0)")"
    assert_eq "${R} main ↑2 ${SYM} " "${out}" "ahead of upstream"
    git -C "${R}" reset -q --hard origin/main
    W="${T_TMP}/other"
    git clone -q "${T_TMP}/remote.git" "${W}" 2>/dev/null
    git -C "${W}" commit -q --allow-empty -m remote1
    git -C "${W}" push -q origin main 2>/dev/null
    git -C "${R}" fetch -q origin
    out="$(plain <<<"$(render "${R}" 0)")"
    assert_eq "${R} main ↓1 ${SYM} " "${out}" "behind upstream"

    # detached HEAD shows a short SHA
    git -C "${R}" checkout -q --detach HEAD
    sha="$(git -C "${R}" rev-parse --short=7 HEAD)"
    assert_eq "${R} @${sha} ${SYM} " "$(plain <<<"$(render "${R}" 0)")" "detached HEAD shows @sha"

    # merge conflict
    git -C "${R}" checkout -q main
    git -C "${R}" reset -q --hard origin/main 2>/dev/null
    git -C "${R}" checkout -q -b c1 && printf 'x\n' >"${R}/c" && git -C "${R}" commit -q -am c1
    git -C "${R}" checkout -q main && git -C "${R}" checkout -q -b c2 && printf 'y\n' >"${R}/c" && git -C "${R}" commit -q -am c2
    git -C "${R}" merge c1 >/dev/null 2>&1
    out="$(render "${R}" 0)"
    assert_contains "$(plain <<<"${out}")" "=1" "conflict counted"
    assert_contains "${out}" $'\e[38;2;255;82;82mc2' "conflict branch drawn in error color"
    git -C "${R}" merge --abort 2>/dev/null

    # hostile branch name: % and shell metacharacters
    git -C "${R}" checkout -q main
    # shellcheck disable=SC2016  # the $( ) is deliberately literal: it is the hostile branch name
    git -C "${R}" checkout -q -b 'feat/100%-x$(>PWNED)'
    out="$(plain <<<"$(render "${R}" 0 PROMPT_SUBST_TEST=1)")"
    assert_contains "${out}" 'feat/100%-x' "percent in a branch name shown literally"
    assert_no_path "${R}/PWNED" "branch name cannot run code"
    sub="$(env -i HOME="${HOME}" PATH="${PATH}" LC_ALL=C.UTF-8 COLUMNS=100 zsh -f -i -c "setopt PROMPT_SUBST; source '${ZDIR}/zackos.zsh'; cd '${R}'; _zackos_prompt_precmd; print -r -- \"\${(e)\${(%)PROMPT}}\"" 2>&1)"
    assert_no_path "${R}/PWNED" "even with PROMPT_SUBST the branch name cannot run code"
    : "${sub}"
    git -C "${R}" checkout -q main

    # long branch name is shortened
    git -C "${R}" checkout -q -b 'feature/a-really-long-branch-name-for-testing'
    assert_contains "$(plain <<<"$(render "${R}" 0)")" "feature/a-really-long-b…" "long branch shortened"
    git -C "${R}" checkout -q main

    # narrow terminal: no git segment
    out="$(plain <<<"$(render "${R}" 0 COLUMNS=40)")"
    assert_eq "${R} ${SYM} " "${out}" "narrow terminal omits the git segment"

    # knobs
    assert_eq "${R} ${SYM} " "$(plain <<<"$(render "${R}" 0 ZACKOS_PROMPT_GIT=off)")" "ZACKOS_PROMPT_GIT=off"
    printf 'z\n' >"${R}/zz"
    assert_eq "${R} main ${SYM} " "$(plain <<<"$(render "${R}" 0 ZACKOS_PROMPT_GIT=branch)")" "ZACKOS_PROMPT_GIT=branch shows branch without status"
    rm -f "${R}/zz"

    # worktree (".git" is a file)
    git -C "${R}" worktree add -q "${T_TMP}/wt" -b wtb 2>/dev/null
    assert_contains "$(plain <<<"$(render "${T_TMP}/wt" 0)")" "wtb" "git worktree detected"

    # git absent from PATH: prompt still works, segment omitted
    mkdir -p "${T_TMP}/nogit"
    ZSH_BIN="$(command -v zsh)"
    out="$(env -i HOME="${HOME}" PATH="${T_TMP}/nogit" LC_ALL=C.UTF-8 COLUMNS=100 "${ZSH_BIN}" -f -i -c "source '${ZDIR}/zackos.zsh'; cd '${R}'; _zackos_prompt_precmd; print -r -- \"\${(%)PROMPT}\"" 2>&1 | sed -e $'s/\x1b\\[[0-9;]*m//g')"
    assert_eq "${R} main ${SYM} " "${out}" "git not installed: branch still read from .git/HEAD, no error"
fi

t_finish
