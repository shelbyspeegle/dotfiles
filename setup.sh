#!/usr/bin/env bash

# shellcheck disable=SC1091
source "./scripts/.with-logging"

# Inputs
########################################################################################################################
REPO="${HOME}/source/dotfiles"
SHELL__CONFIG_FILENAME=".zshrc"
SCRIPTS_DIRNAME="scripts"

REPO__SHELL_CONFIG="${REPO}/${SHELL__CONFIG_FILENAME}" # e.g., ~/source/dotfiles/.zshrc
HOME__SHELL_CONFIG="${HOME}/${SHELL__CONFIG_FILENAME}" # e.g., ~/.zshrc
HOME__SHELL_CONFIG_PRIVATE="${HOME__SHELL_CONFIG}.private" # e.g., ~/.zshrc.private

REPO__SCRIPTS_DIR="${REPO}/${SCRIPTS_DIRNAME}" # e.g., ~/source/dotfiles/scripts
HOME__SCRIPTS_DIR="${HOME}/${SCRIPTS_DIRNAME}" # e.g., ~/scripts

# Initialize
echo
echo "Initializing dotfiles..."
echo

if [[ ! -d "${REPO}" ]]; then
  echo_error "Repository not found (${REPO}). Exiting..."
  exit 1;
fi

if [[ -f "${HOME__SHELL_CONFIG}" ]]; then
  echo_step "Backing up existing dotfile to ${HOME__SHELL_CONFIG}.backup..."
  mv "$HOME__SHELL_CONFIG" "${HOME__SHELL_CONFIG}.backup"
  echo_success "Backup created."
fi
echo

echo_step "Linking dotfile ${HOME__SHELL_CONFIG} -> ${REPO__SHELL_CONFIG}"
ln -s "${REPO__SHELL_CONFIG}" "$HOME__SHELL_CONFIG"
echo_success "Link created."
echo

echo_step "Setting up private dotfile ($HOME__SHELL_CONFIG_PRIVATE)"
if [[ -f "${HOME__SHELL_CONFIG_PRIVATE}" ]]; then
  echo_success "File found. Continuing..."
else
  echo_step "File not found. Creating..."
  touch "${HOME__SHELL_CONFIG_PRIVATE}"
  echo_success "Private config file created."
fi
echo

# Connect scripts.
########################################################################################################################
echo_step "Linking scripts (${HOME__SCRIPTS_DIR})"
if [[ -d "${HOME__SCRIPTS_DIR}" ]]; then
  # Check if it's already a symlink to our repo
  if [[ -L "${HOME__SCRIPTS_DIR}" && "$(readlink "${HOME__SCRIPTS_DIR}")" == "${REPO__SCRIPTS_DIR}" ]]; then
    echo_success "Directory is already correctly linked. Continuing..."
  else
    echo_step "Existing ~/scripts directory found. Backing it up to ${HOME__SCRIPTS_DIR}.backup..."
    # Remove any existing backup first to prevent "are identical" errors
    if [[ -d "${HOME__SCRIPTS_DIR}.backup" ]]; then
      rm -rf "${HOME__SCRIPTS_DIR}.backup"
    fi
    mv "${HOME__SCRIPTS_DIR}" "${HOME__SCRIPTS_DIR}.backup"
    echo_success "Backup created."
  fi
fi
echo

# Only create symlink if it doesn't already exist
echo_step "linking local .zshrc to repo"
if [[ ! -L "${HOME__SCRIPTS_DIR}" || "$(readlink "${HOME__SCRIPTS_DIR}")" != "${REPO__SCRIPTS_DIR}" ]]; then
  echo_step "Creating symlink..."
  ln -s "${REPO__SCRIPTS_DIR}" "${HOME__SCRIPTS_DIR}"
  echo_success "Symlink created."
else
  echo_success "Symlink already exists. Continuing..."
fi
echo

# Initialize shell
########################################################################################################################

# Set up auto-completion for zsh if not already set up
echo_step "[zsh] Setting up auto complete..."
if [ ! -d "${HOME}/.zsh/zsh-autosuggestions" ]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions "${HOME}/.zsh/zsh-autosuggestions"
fi
zsh "${HOME}/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
echo_success "Autocomplete setup complete."
echo

# Set up syntax-highlighting for zsh if not already set up
echo_step "[zsh] Seting up syntax highlighting..."
if [ ! -d "${HOME}/.zsh/zsh-syntax-highlighting" ]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${HOME}/.zsh/zsh-syntax-highlighting"
fi
zsh "${HOME}/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
echo_success "Autocomplete setup complete."
echo

echo_success "Dotfiles setup complete!"