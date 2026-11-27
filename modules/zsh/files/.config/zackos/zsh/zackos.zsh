# SPDX-License-Identifier: GPL-3.0-or-later
# ZackOS zsh additions. Opt-in: add this single line to your own ~/.zshrc:
#     source "${XDG_CONFIG_HOME:-$HOME/.config}/zackos/zsh/zackos.zsh"
# ZackOS never edits ~/.zshrc and never runs chsh.

_zackos_dir="${${(%):-%x}:A:h}"
[[ -r "${_zackos_dir}/zackos-theme.zsh" ]] && source "${_zackos_dir}/zackos-theme.zsh"

setopt HIST_IGNORE_DUPS HIST_REDUCE_BLANKS SHARE_HISTORY INTERACTIVE_COMMENTS
: "${HISTFILE:=${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history}"
: "${HISTSIZE:=10000}" "${SAVEHIST:=10000}"
[[ -d "${HISTFILE:h}" ]] || mkdir -p -- "${HISTFILE:h}"

# Prompt (see prompt.zsh): interactive shells only; ZACKOS_PROMPT=0 keeps your own prompt.
# Without the palette variables, prompt.zsh leaves your prompt untouched.
if [[ -o interactive && "${ZACKOS_PROMPT:-1}" != 0 && -r "${_zackos_dir}/prompt.zsh" ]]; then
  source "${_zackos_dir}/prompt.zsh"
fi
unset _zackos_dir
