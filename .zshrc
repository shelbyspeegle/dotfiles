#!/bin/bash

########################################################################################################################
# Prompt - "oh my posh"
########################################################################################################################
# Clear a bunch of lines so prompt starts at bottom.
# printf '\n%.0s' {1..100}
# Load custom theme.
eval "$(oh-my-posh init zsh --config ~/source/_personal/dotfiles/mytheme.omp.json)"

# Set up auto complete.
# git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#555555'

# Set up syntax highlighting.
# git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.zsh/zsh-syntax-highlighting
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh




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
alias s="cd ~/source"
alias ls='ls -G'
alias zs='source ~/.zshrc'
alias zc='code ~/.zshrc'
alias up="echo 'Pinging Google' && ping www.google.com";

alias uncommit='git reset HEAD~1 --soft'
wifi() {
  local interface="en0"
  echo "Disabling Wi-Fi..."
  sudo ifconfig $interface down

  echo "Flushing network routes and cache..."
  sudo route flush
  sudo dscacheutil -flushcache

  echo "Re-enabling Wi-Fi..."
  sudo ifconfig $interface up

  echo "Rebinding to DHCP..."
  sudo networksetup -setdhcp Wi-Fi

  echo "Checking for an IP address..."
  ifconfig $interface | grep inet || echo "No IP address assigned."

  echo "Reset complete!"
}

export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# sst
export PATH=/Users/sspeegle/.sst/bin:$PATH

# This will allow you to execute your scripts in ~/scripts/ by simply typing scriptname in the bash.
export PATH=$PATH:~/scripts
