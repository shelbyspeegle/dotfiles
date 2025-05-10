#!/bin/bash

# zshrc
mv ~/.zshrc ~/.zshrc.backup
ln -s ~/source/dotfiles/.zshrc ~/.zshrc

touch ~/.zshrc.private
