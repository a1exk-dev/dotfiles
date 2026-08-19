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

unset -f fuck 2>/dev/null

if [[ -x /usr/bin/thefuck ]]; then
	# Reviewed static The Fuck 3.32 integration from thefuck/shells/bash.py.
	fuck() {
		TF_PYTHONIOENCODING=$PYTHONIOENCODING
		export TF_SHELL=bash
		export TF_ALIAS=fuck
		export TF_SHELL_ALIASES=$(alias)
		export TF_HISTORY=$(fc -ln -10)
		export PYTHONIOENCODING=utf-8
		TF_CMD=$(
			/usr/bin/thefuck THEFUCK_ARGUMENT_PLACEHOLDER "$@"
		) && eval "$TF_CMD"
		unset TF_HISTORY
		export PYTHONIOENCODING=$TF_PYTHONIOENCODING
		history -s $TF_CMD
	}
fi
