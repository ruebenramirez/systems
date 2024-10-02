# The base toolchain that I expect on a system
{ config, pkgs, ... }:

let

in
{
  environment.systemPackages = with pkgs; [
    black # python linter
    btop
    cargo # rust app dev lifecycling
    cmake
    ctags
    difftastic
    dig # query dns
    dmidecode # reads info from connected hardware
    file
    fish # Fish shell
    fzf # fuzzy finder - supports ctrl-r for fish shell
    git
    git-lfs
    gnumake
    grc
    htop # system resource monitoring tool
    imagemagick
    iotop # disk io performance monitor tool
    jq
    keychain # remember my ssh key passphrases
    ldns
    lshw
    lsof
    manix # useful search for nix docs
    mosh # lightweight ssh for remoting over slow or unstable networks
    ncdu
    neovim
    nethogs # network traffic monitoring tool
    nixpkgs-fmt
    nmap
    openssl
    parted # manage disk partitions
    pciutils # contains the lspci tool
    powertop # power management profiling tool
    qrtool # generate qr code images on the command line
    rclone
    rtorrent
    shellcheck
    silver-searcher
    stow
    tig # ncurses git repo viewer
    tmux
    tree
    unzip
    usbutils # contains lsusb tool
    uutils-coreutils-noprefix
    wget
    yt-dlp # download youtube video/audio
  ];

  programs.direnv.enable = true;

  # neovim config
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    configure = {
      customRC = ''
        "set nowrap
        set hlsearch
        "set vi+=n
        filetype off                  " required!
        set backspace=indent,eol,start
        set ignorecase
        set cursorline
        set encoding=utf-8
        set paste
        set nospell
        set textwidth=90

        set number
        set numberwidth=3
        set cc=80
        "set list
        "set listchars=tab:→\ ,space:·,nbsp:␣,trail:•,eol:¶,precedes:«,extends:»

        syntax on
        if &diff
          colorscheme blue
        endif


        """""""""""""""""""""""""""""""""""""
        " indentation: use spaces instead of tabs
        """""""""""""""""""""""""""""""""""""
        set expandtab
        set tabstop=4
        set shiftwidth=4
        set softtabstop=4

        " set 2 space tabs when appropriate
        autocmd FileType *.nix,nix,go,r,R,yml,yaml,json,markdown,ruby,javascript,Rakefile setlocal shiftwidth=2 tabstop=2 softtabstop=2 showtabline=2

        " set 4 space tabs when appropriate
        autocmd FileType python,*.py.tpl setlocal tabstop=4 expandtab shiftwidth=4 softtabstop=4 showtabline=4


        " Remove end of line whitespace on save
        autocmd BufWritePre * :%s/\s\+$//e

        " format python code with Black on save
        "autocmd BufWritePre * :Black


        " Better diff highlighting
        highlight! link DiffText MatchParen

        """""""""""""""""""""""""""""""""""""
        " NERDtree config
        """""""""""""""""""""""""""""""""""""
        " default larger window  width
        let g:NERDTreeWinSize = 40


        """""""""""""""""""""""""""""""""""""
        " highlight characters past column 80
        " http://unlogic.co.uk/2013/02/08/vim-as-a-python-ide/
        """""""""""""""""""""""""""""""""""""
        " augroup vimrc_autocmds
        "     autocmd!
        "     autocmd FileType python highlight OverLength ctermfg=white ctermbg=red guibg=#592929
        "     autocmd FileType python match OverLength /\%81v.\+/
        "     "autocmd FileType python set nowrap
        "     augroup END

        """"""""""""""""""""""""""""""""""""""
        " Terraform formatting
        """"""""""""""""""""""""""""""""""""""
        let g:terraform_align=1
        let g:terraform_fmt_on_save=1


        """"""""""""""""""""""""""""""""""""""
        " Leader keyboard shortcuts
        """"""""""""""""""""""""""""""""""""""

        "set timeoutlen=500
        let mapleader = ","

        " close file
        nnoremap <leader>q :q<cr>

        " save file
        nnoremap <leader>s :w<cr>

        " new tab
        nnoremap <leader>t :Tex<cr>

        " horizontal split
        nnoremap <leader>h :sp<cr>

        " vertical split
        nnoremap <leader>v :vsp<cr>

        " insert date
        nnoremap <leader>d :put =strftime('%Y-%m-%d')<CR>

        " Go to tab by number
        noremap <leader>1 1gt
        noremap <leader>2 2gt
        noremap <leader>3 3gt
        noremap <leader>4 4gt
        noremap <leader>5 5gt
        noremap <leader>6 6gt


        " navigation with control keys
        nnoremap <C-J> <C-W><C-J>
        nnoremap <C-K> <C-W><C-K>
        nnoremap <C-L> <C-W><C-L>
        nnoremap <C-H> <C-W><C-H>

        nmap <F8> :TagbarToggle<CR>
      '';

      packages.myVimPackage = with pkgs.vimPlugins; {
        start = [
          ctrlp
          vim-tmux-navigator
          vim-dirdiff
          vim-commentary
          vim-signify
          nerdtree
          vim-endwise
          vim-easymotion
          tagbar
        ];
      };
    };
  };

  # use Fish shell
  users.defaultUserShell = pkgs.fish;
  programs.fish.enable = true;

  services.tailscale.enable = true;

  environment.variables = {
    EDITOR="vim";
  };
}


