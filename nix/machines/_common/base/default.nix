# The base toolchain that I expect on a system
{ config, pkgs, pkgs-unstable, ... }:

let

in
{

  imports = [
    ./editor.nix
    ./gpg.nix
    ./tmux.nix
  ];

  environment.systemPackages = with pkgs; [
    awscli2
    bc
    bchunk
    black # python linter
    btop
    cmake
    ctags
    difftastic
    dig # query dns
    dmidecode # reads info from connected hardware
    file
    fish # Fish shell
    fishPlugins.z
    fzf # fuzzy finder - supports ctrl-r for fish shell
    gh
    git
    git-lfs
    glab
    gnumake
    grc
    htop # system resource monitoring tool
    icdiff
    imagemagick
    iotop # disk io performance monitor tool
    pkgs-unstable.jujutsu
    jjui
    jq
    keychain # remember my ssh key passphrases
    ldns
    lshw
    lsof
    magic-wormhole
    manix # useful search for nix docs
    mosh
    ncdu
    nethogs # network traffic monitoring tool
    nixpkgs-fmt
    nixpkgs-review
    nmap
    openssl
    p7zip
    parted # manage disk partitions
    pciutils # contains the lspci tool
    pigz
    powertop # power management profiling tool
    qrtool # generate qr code images on the command line
    rclone
    ripgrep-all
    rtorrent
    shellcheck
    silver-searcher
    speedtest-cli # test internet connection bandwidth
    stow
    tig # ncurses git repo viewer
    tree
    unzip
    usbutils # contains lsusb tool
    uutils-coreutils-noprefix
    wget
    yazi # file browser
    zoxide
    yt-dlp # download youtube video/audio

    # zfs sanoid/syncoid backup related
    lzop
    mbuffer
    pv
    sanoid

    # Network and VPN
    tailscale
    wireguard-tools

    # dev related
    nerdctl
  ];

  programs.direnv.enable = true;

  # use Fish shell
  users.defaultUserShell = pkgs.fish;
  programs.fish.enable = true;
  # disable long man cache build times when using fish shell
  documentation.man.generateCaches = false;

  # part of gnupg reqs
  services.pcscd.enable = true;
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    # pinentryFlavor = "tty";
    # Make pinentry across multiple terminal windows, seamlessly
    enableSSHSupport = true;
  };

  programs.mosh.enable = true;
}
