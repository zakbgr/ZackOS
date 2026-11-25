# SPDX-License-Identifier: GPL-3.0-or-later
# ZackOS zsh additions. Opt-in: add this single line to your own ~/.zshrc:
#     source "${XDG_CONFIG_HOME:-$HOME/.config}/zackos/zsh/zackos.zsh"
# ZackOS never edits ~/.zshrc and never runs chsh.

_zackos_dir="${${(%):-%x}:A:h}"
[[ -r "${_zackos_dir}/zackos-theme.zsh" ]] && source "${_zackos_dir}/zackos-theme.zsh"
unset _zackos_dir

setopt HIST_IGNORE_DUPS HIST_REDUCE_BLANKS SHARE_HISTORY INTERACTIVE_COMMENTS
: "${HISTFILE:=${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history}"
: "${HISTSIZE:=10000}" "${SAVEHIST:=10000}"
[[ -d "${HISTFILE:h}" ]] || mkdir -p -- "${HISTFILE:h}"

# Prompt: only when the palette variables exist; otherwise the user's prompt is untouched.
if [[ -n "${ZACKOS_FG_ACCENT:-}" ]]; then
  PROMPT=$'%{\e['"${ZACKOS_FG_ACCENT}"$'m%}%~%{\e[0m%} %(?.%{\e['"${ZACKOS_FG_GREEN}"$'m%}.%{\e['"${ZACKOS_FG_ERROR}"$'m%})%#%{\e[0m%} '
fi
