# ---- basic Zsh behavior ----

# Path to the file where Zsh stores command history
HISTFILE=~/.zsh_history
# Number of commands kept in memory during the session
HISTSIZE=50000
# Number of commands saved to the history file on disk
SAVEHIST=50000
# Remove older duplicates from history when a command is repeated
setopt HIST_IGNORE_ALL_DUPS
# Do not write duplicate commands to the history file
setopt HIST_SAVE_NO_DUPS
# Share command history instantly between all open Zsh sessions
setopt SHARE_HISTORY
# Append each command to the history file immediately after execution
setopt INC_APPEND_HISTORY

# Prepare Zsh's programmable completion system for loading
autoload -Uz compinit
# Initialize command and option tab-completion
compinit

# ---- zinit (self-bootstrapping) ----
ZINIT_HOME="$HOME/.local/share/zinit/zinit.git"
if ! command -v zinit >/dev/null 2>&1; then
  if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$HOME/.local/share/zinit"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
  fi
fi
if [ -f "$ZINIT_HOME/zinit.zsh" ]; then
  source "$ZINIT_HOME/zinit.zsh"
fi

# zsh plugins
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light Aloxaf/fzf-tab
zinit light ajeetdsouza/zoxide

# fzf shell integration (keybindings + completion)
if [ -f /usr/share/fzf/shell/key-bindings.zsh ]; then
  source /usr/share/fzf/shell/key-bindings.zsh
fi
if [ -f /usr/share/fzf/shell/completion.zsh ]; then
  source /usr/share/fzf/shell/completion.zsh
fi

# thefuck init
eval "$(thefuck --alias)"

# zoxide init
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

# Should be last
eval "$(starship init zsh)"
export PATH=$PATH:$HOME/.local/bin

# opencode
export PATH=/home/a1exk/.opencode/bin:$PATH
