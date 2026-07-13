#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto -l'
alias lsa='ls --color=auto -la'
alias grep='grep --color=auto'
alias n='nvim .'
alias ..='cd ..'
alias mv='mv -i'

alias g='git'
alias gs='git status'
alias ga='git add .'
alias gcm='git commit -m'

alias ch='chromium'

#ask() { claude -p "$*"; }

# Separate Claude Code accounts (isolated config/credentials/history per dir)
alias eclaude='CLAUDE_CONFIG_DIR="$HOME/.claude" claude'           # echandia (existing login)
alias cclaude='CLAUDE_CONFIG_DIR="$HOME/.claude-creekside" claude' # creekside (logs in on first run)

 PS1='\[\033[1;34m\]$(pwd | awk -F/ '\''{if (NF>2) print $(NF-1)"/"$(NF); else print $NF}'\'')\[\033[0m\] \$ '

PATH=$PATH:~/src/scripts/linux
PATH=$PATH:~/src/enigmaOS/scripts
PATH=$PATH:~/src/scripts/linux/edit
PATH=$PATH:~/src/scripts/linux/work/echandia
PATH=$PATH:~/src/scripts/linux/work/creekside
PATH=$PATH:~/go/bin
export PATH="$HOME/.local/bin:$PATH"
export EDITOR=nvim
