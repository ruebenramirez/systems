SHELL := /usr/bin/env bash

DIR=$(pwd)


power-management:
	sudo systemctl enable tlp
	sudo systemctl start tlp
	sudo systemctl status tlp
	#sudo powertop

firmware-update:
	- fwupdmgr get-devices
	- fwupdmgr refresh --force
	- fwupdmgr get-updates --force
	- fwupdmgr update

macbookpro_keyboard:
	/usr/bin/env python3 /home/rramirez/bin/setup-apple-keyboard.py

git-config:
	- git config --global user.name "Rueben Ramirez"
	- git config --global user.email ruebenramirez@gmail.com
	- git config --global core.editor nvim
	- git config --global color.ui true
	- git config --global pull.rebase true
	- git config --global --replace-all core.pager "less -F -X"
	- git config --global init.defaultBranch master
	- git config --global credential.helper store

customBins:
	- sudo unlink ~/bin
	- rm -fr ~/bin
	ln -sf $$(pwd)/bin ~/bin

macos-faster-key-repeat:
	defaults write -g InitialKeyRepeat -int 10 # normal minimum is 15 (225 ms)
	defaults write -g KeyRepeat -int 1 # normal minimum is 2 (30 ms)
