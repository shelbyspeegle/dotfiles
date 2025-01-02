#!/bin/bash

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ZSH STUFF ############################################################
export ZSH="/Users/sspeegle/.oh-my-zsh"
ZSH_THEME="powerlevel10k"
test -e "${HOME}/powerlevel10k" && source "${HOME}/powerlevel10k/powerlevel10k.zsh-theme"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

POWERLEVEL9K_MODE='nerdfont-complete'
POWERLEVEL9K_PROMPT_ON_NEWLINE=true # so i can get > on line after main info.
POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX="" # overwrite╭─
POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX=" %B%F{cyan}❯%b " # > bold

# don't show git icons,
POWERLEVEL9K_VCS_GIT_ICON=''
POWERLEVEL9K_VCS_GIT_GITHUB_ICON=''
POWERLEVEL9K_VCS_GIT_GITLAB_ICON=''

# format date to hh:mm - 12 hr format. default=%D{%d.%m.%y}
# POWERLEVEL9K_DATE_FORMAT=%D{%d.%m.%y}
typeset -g POWERLEVEL9K_TIME_FOREGROUND=7 # white
typeset -g POWERLEVEL9K_TIME_BACKGROUND=000 # black

typeset -g POWERLEVEL9K_DIR_FOREGROUND=000
typeset -g POWERLEVEL9K_DIR_ANCHOR_FOREGROUND=000
typeset -g POWERLEVEL9K_DIR_SHORTENED_FOREGROUND=000

typeset -g POWERLEVEL9K_DIR_ANCHOR_BOLD=false

# Print all colors:
# 
# for i in {0..255}; do print -Pn "%K{$i}  %k%F{$i}${(l:3::0:)i}%f " ${${(M)$((i%6)):#3}:+$'\n'}; done
# 011 = bright yellow
# 009 = bright red

# color if error code returned.
typeset -g POWERLEVEL9K_STATUS_ERROR_BACKGROUND=009
typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_BACKGROUND=009
typeset -g POWERLEVEL9K_STATUS_ERROR_FOREGROUND=220
typeset -g POWERLEVEL9K_STATUS_ERROR_SIGNAL_FOREGROUND=220


# shorten path.
# POWERLEVEL9K_SHORTEN_STRATEGY=truncate_from_right
# POWERLEVEL9K_SHORTEN_DELIMITER=…
# POWERLEVEL9K_SHORTEN_DIR_LENGTH=4

# turn off some icons
POWERLEVEL9K_HOME_ICON=''
POWERLEVEL9K_HOME_SUB_ICON=''
POWERLEVEL9K_FOLDER_ICON=''
POWERLEVEL9K_ETC_ICON=''

typeset -ga POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(
  dir                     # current directory
  status                  # exit code of the last command
  newline
)

typeset -ga POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(
  time                    # current time
  command_execution_time  # duration of the last command (default POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD is 3s)
  # vcs                   # git status
  # context               # user@host
)

# 🧑‍💻 FROM https://github.com/kentcdodds/dotfiles/blob/main/.zshrc ######################################################

# history size
HISTSIZE=5000
HISTFILESIZE=10000

SAVEHIST=5000
setopt EXTENDED_HISTORY
HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history
# share history across multiple zsh sessions
setopt SHARE_HISTORY
# append to history
setopt APPEND_HISTORY
# adds commands as they are typed, not at shell exit
setopt INC_APPEND_HISTORY
# do not store duplications
setopt HIST_IGNORE_DUPS

# disable https://scarf.sh/
SCARF_ANALYTICS=false

########################################################################################################################

source ~/.zshrc.private

# OTHER STUFF ##########################################################

# Aliases
alias ls='ls -G'
alias zs='source ~/.zshrc'
alias zc='code ~/.zshrc'
alias uncommit='git reset HEAD~1 --soft'

export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# sst
export PATH=/Users/sspeegle/.sst/bin:$PATH

# This will allow you to execute your scripts in ~/scripts/ by simply typing scriptname in the bash.
export PATH=$PATH:~/scripts

# pnpm
export PNPM_HOME="/Users/sspeegle/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
