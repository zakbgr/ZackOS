# SPDX-License-Identifier: GPL-3.0-or-later
#
# ZackOS prompt. Loaded by zackos.zsh in interactive shells only.
#
#   <directory> <git branch and status> <symbol>
#
# - Colors come from the ZACKOS_FG_* variables of zackos-theme.zsh (generated from the palette).
#   If they are missing, the user's own prompt is left untouched.
# - No dependency except an optional git. Without git (or with ZACKOS_PROMPT_GIT=branch) the
#   branch is read from .git/HEAD in pure zsh. No vcs_info, no PROMPT_SUBST, no history changes,
#   no shell options changed.
# - The previous command's status is drawn with %?, which zsh evaluates when the prompt is shown,
#   so other precmd hooks cannot disturb it. Failure is shown by a red symbol AND the exit code,
#   not by color alone.
# - Every escape sequence is wrapped in %{ %} so zsh measures the prompt width correctly.
# - Untrusted text (branch names can contain $, `, ( ) ...) is reduced to a safe character set,
#   so a hostile repository cannot run code even if the user enabled PROMPT_SUBST.
#
# Switches:  ZACKOS_PROMPT=0 (do not load; honoured by zackos.zsh)
#            ZACKOS_PROMPT_GIT=full (default) | branch | off

[[ -n "${ZACKOS_FG_ACCENT:-}" && -n "${ZACKOS_FG_GREEN:-}" && -n "${ZACKOS_FG_MUTED:-}" &&
   -n "${ZACKOS_FG_WARNING:-}" && -n "${ZACKOS_FG_ERROR:-}" ]] || return 0

autoload -Uz add-zsh-hook
zmodload zsh/langinfo 2>/dev/null

# ---- building blocks (computed once) -------------------------------------------------------
typeset -g _ZP_RST=$'%{\e[0m%}'
typeset -g _ZP_ACC=$'%{\e['"${ZACKOS_FG_ACCENT}"$'m%}'
typeset -g _ZP_GRN=$'%{\e['"${ZACKOS_FG_GREEN}"$'m%}'
typeset -g _ZP_MUT=$'%{\e['"${ZACKOS_FG_MUTED}"$'m%}'
typeset -g _ZP_WRN=$'%{\e['"${ZACKOS_FG_WARNING}"$'m%}'
typeset -g _ZP_ERR=$'%{\e['"${ZACKOS_FG_ERROR}"$'m%}'

if [[ "${(L)langinfo[CODESET]:-}" == (utf-8|utf8) ]]; then
  typeset -g _ZP_SYM='❯' _ZP_ELL='…' _ZP_UP='↑' _ZP_DOWN='↓'
else
  typeset -g _ZP_SYM='>' _ZP_ELL='...' _ZP_UP='^' _ZP_DOWN='v'
fi

# ---- git segment ----------------------------------------------------------------------------
# Sets REPLY to the colored segment (empty outside a repository). Returns 0 always.
_zackos_prompt_git() {
  emulate -L zsh
  REPLY=''
  local mode="${ZACKOS_PROMPT_GIT:-full}"
  [[ "${mode}" == off ]] && return 0
  (( ${COLUMNS:-80} >= 50 )) || return 0          # narrow terminal: directory and symbol only

  # Find the repository by walking up in pure zsh: no process is started outside a repository.
  local d="${PWD}" gitdir='' l
  while :; do
    if [[ -d "${d}/.git" ]]; then
      gitdir="${d}/.git"
      break
    elif [[ -f "${d}/.git" ]]; then                # worktree or submodule: ".git" is a file
      read -r l <"${d}/.git" 2>/dev/null
      [[ "${l}" == 'gitdir: '* ]] || return 0
      gitdir="${l#gitdir: }"
      [[ "${gitdir}" == /* ]] || gitdir="${d}/${gitdir}"
      break
    fi
    [[ "${d}" == / ]] && return 0
    d="${d:h}"
  done

  local branch='' oid='' state_color="${_ZP_GRN}" markers=''
  integer staged=0 modified=0 untracked=0 conflicts=0 ahead=0 behind=0

  if [[ "${mode}" == full ]] && (( ${+commands[git]} )); then
    local out line xy
    out="$(command git --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)" || return 0
    for line in "${(@f)out}"; do
      case "${line}" in
        '# branch.oid '*)  oid="${line#\# branch.oid }" ;;
        '# branch.head '*) branch="${line#\# branch.head }" ;;
        '# branch.ab '*)
          ahead="${${line#\# branch.ab +}%% *}"
          behind="${line##* -}" ;;
        '1 '* | '2 '*)
          xy="${line[3,4]}"
          [[ "${xy[1]}" != . ]] && (( staged++ ))
          [[ "${xy[2]}" != . ]] && (( modified++ )) ;;
        'u '*) (( conflicts++ )) ;;
        '? '*) (( untracked++ )) ;;
      esac
    done
    [[ "${branch}" == '(detached)' ]] && branch=''
    [[ -z "${branch}" ]] && branch="@${oid[1,7]}"
  else
    # Branch only, no status: read HEAD directly.
    read -r l <"${gitdir}/HEAD" 2>/dev/null || return 0
    case "${l}" in
      'ref: refs/heads/'*) branch="${l#ref: refs/heads/}" ;;
      'ref: '*)            branch="${l#ref: }" ;;
      *)                   branch="@${l[1,7]}" ;;
    esac
  fi

  # Reduce untrusted text to a safe character set, shorten it, then escape % for prompt expansion.
  branch="${branch//[^[:alnum:]._\/+@=#%-]/?}"
  (( ${#branch} > 24 )) && branch="${branch[1,23]}${_ZP_ELL}"
  branch="${branch//\%/%%}"

  if (( conflicts )); then state_color="${_ZP_ERR}"
  elif (( staged || modified || untracked )); then state_color="${_ZP_WRN}"
  fi
  (( staged ))    && markers+=" ${_ZP_GRN}+${staged}"
  (( modified ))  && markers+=" ${_ZP_WRN}!${modified}"
  (( conflicts )) && markers+=" ${_ZP_ERR}=${conflicts}"
  (( untracked )) && markers+=" ${_ZP_MUT}?${untracked}"
  (( ahead ))     && markers+=" ${_ZP_ACC}${_ZP_UP}${ahead}"
  (( behind ))    && markers+=" ${_ZP_ACC}${_ZP_DOWN}${behind}"

  REPLY="${state_color}${branch}${markers}${_ZP_RST}"
  return 0
}

# ---- prompt assembly (runs before every prompt) --------------------------------------------
_zackos_prompt_precmd() {
  emulate -L zsh
  local REPLY git='' sym="${_ZP_SYM}"
  (( EUID == 0 )) && sym='#'
  _zackos_prompt_git && git="${REPLY}"
  # %(4~|a|b): paths with 4+ components are shortened to first/…/last two.
  # %(?|ok|failed): evaluated by zsh at display time, so it reflects the real last status.
  PROMPT="${_ZP_ACC}%(4~|%-1~/${_ZP_ELL}/%2~|%~)${_ZP_RST}${git:+ ${git}} %(?|${_ZP_GRN}${sym}${_ZP_RST}|${_ZP_ERR}[%?] ${sym}${_ZP_RST}) "
}

add-zsh-hook precmd _zackos_prompt_precmd   # idempotent: a second source does not add a second hook
_zackos_prompt_precmd
