# Omarchy environment (OMARCHY_PATH + PATH), needed even for non-interactive shells
[[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] && source /usr/share/omarchy/default/bash/env-bootstrap

# If not running interactively, don't do anything else (leave this above the rc source)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
if [[ -z ${DOTFILES_OMARCHY_BASH_RC_LOADED-} ]]; then
	DOTFILES_OMARCHY_BASH_RC_LOADED=1
	source "$OMARCHY_PATH/default/bash/rc"
fi

# Add your own exports, aliases, and functions here.
alias vi='nvim'
alias ll='lsa'
alias ~='cd ~'
