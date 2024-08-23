# The base toolchain that I expect on a system
{ config, pkgs, ... }:

let
  # Need the pythons in my vims
  myVim = pkgs.vim_configurable.override { pythonSupport = true; };
in
{
  # install Nebulaworks packages
  environment.systemPackages = with pkgs; [
    ncdu
    btop
    dig
    file
    wget
    git
    git-lfs
    ldns
    tmux
    silver-searcher
    stow
    gnumake
    jq
    lsof
    myVim # Custom vim
    nixpkgs-fmt
    openssl
    shellcheck
    tree
    manix # useful search for nix docs
    unzip
    iotop # disk io performance monitor tool
    htop # system resource monitoring tool
    nethogs # network traffic monitoring tool
    black # python linter
    ctags
    cmake
    mosh # lightweight ssh for remoting over slow or unstable networks
    cargo # rust app dev lifecycling
    fish # Fish shell
    fzf # fuzzy finder - supports ctrl-r for fish shell
    keychain # remember my ssh key passphrases
    tig # ncurses git repo viewer
    parted # manage disk partitions
    yt-dlp # download youtube video/audio
    grc
    difftastic
    imagemagick
    rtorrent
  ];

  programs.direnv.enable = true;


  # use Fish shell
  users.defaultUserShell = pkgs.fish;
  programs.fish.enable = true;

  services.tailscale.enable = true;

  environment.variables = {
    EDITOR="vim";
  };
}


