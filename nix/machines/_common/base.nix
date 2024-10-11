# The base toolchain that I expect on a system
{ config, pkgs, ... }:

let

in
{
  environment.systemPackages = with pkgs; [
    bchunk
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
    p7zip
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
        set background=light " better colors for a white background
        set backspace=indent,eol,start " allow backspacing over these

        set cursorline " underline the line that the cursor is currently on
        set encoding=utf-8
        set paste
        set number
        set numberwidth=3

        set list " show invisible characters

        syntax on " enable syntax highlighting

        if &diff
          colorscheme blue
        endif

        " better searching
        set hlsearch " highlight search terms
        highlight! link DiffText MatchParen " Better diff highlighting
        set ignorecase " search without case sensitivity


        " indentation: use spaces instead of tabs
        set expandtab
        set tabstop=4
        set shiftwidth=4
        set softtabstop=4

        " set 2 space tabs when appropriate
        autocmd FileType vim,*.nix,nix,go,r,R,yml,yaml,json,markdown,ruby,javascript,Rakefile setlocal shiftwidth=2 tabstop=2 softtabstop=2 showtabline=2

        " set 4 space tabs when appropriate
        "autocmd FileType python,*.py.tpl setlocal tabstop=4 expandtab shiftwidth=4 softtabstop=4 showtabline=4

        autocmd BufWritePre * :%s/\s\+$//e " Remove end of line whitespace on save

        " format python code with Black on save
        autocmd FileType python,*.py.tpl BufWritePre * :Black

        set colorcolumn=80 " visual indicator appears at this column
        set textwidth=90 " controls line wrapping (automatically breaks lines at this column)

        " Terraform formatting
        let g:terraform_align=1
        let g:terraform_fmt_on_save=1


        " Leader keyboard shortcuts
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
        nnoremap <leader>d :put =strftime('%Y-%m-%d')

        " insert datetime
        nnoremap <leader>D :put =strftime('%Y-%m-%d:%H:%M:%S')

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
          nerdtree
          tagbar
          vim-commentary
          vim-dirdiff
          vim-easymotion
          vim-endwise
          vim-signify
          vim-tmux-navigator
        ];
      };
    };
  };

  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [ vim-tmux-navigator ];
    extraConfig = ''
      set -g default-terminal xterm-256color
      set -g status-right "#S:#H"
      set -g status-bg colour40
      setw -g window-status-current-style bg=colour40 # new tmux

      # nested tmux
      bind -n S-left  prev
      bind -n S-right next
      bind -n S-C-left  swap-window -t -1
      bind -n S-C-right swap-window -t +1
      bind -n M-F11 set -qg status-bg colour25
      bind -n M-F12 set -qg status-bg colour40
      bind -n S-up \
        send-keys M-F12 \; \
        set -qg status-bg colour25 \; \
        unbind -n S-left \; \
        unbind -n S-right \; \
        unbind -n S-C-left \; \
        unbind -n S-C-right \; \
        set -qg prefix C-a
      bind -n S-down \
        send-keys M-F11 \; \
        set -qg status-bg colour40 \; \
        bind -n S-left  prev \; \
        bind -n S-right next \; \
        bind -n S-C-left swap-window -t -1 \; \
        bind -n S-C-right swap-window -t +1 \; \
        set -qg prefix C-b

      # Bind reload key
      bind r source-file ~/.tmux.conf \; display-message "Config reloaded..."

      # allow neovim to escape INSERT mode quickly
      set -sg escape-time 0

      # configure default shell (zsh)
      set-option -g default-shell $SHELL

      # switch active pane w/ vim keys
      bind j select-pane -D
      bind k select-pane -U
      bind h select-pane -L
      bind l select-pane -R


      # use Ctrl + vim keys to move around
      is_vim="ps -o state= -o comm= -t '#{pane_tty}' \
          | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|\.?n?vim?x?(-wrapped)?)(diff)?$'"

      is_fzf="ps -o state= -o comm= -t '#{pane_tty}' \
        | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?fzf$'"

      bind -n C-h run "($is_vim && tmux send-keys C-h) || \
                       tmux select-pane -L"

      bind -n C-j run "($is_vim && tmux send-keys C-j)  || \
                       ($is_fzf && tmux send-keys C-j) || \
                       tmux select-pane -D"

      bind -n C-k run "($is_vim && tmux send-keys C-k) || \
                       ($is_fzf && tmux send-keys C-k)  || \
                       tmux select-pane -U"

      bind -n C-l run "($is_vim && tmux send-keys C-l) || \
                       tmux select-pane -R"

      bind -n 'C-\' if-shell "$is_vim" "send-keys 'C-\\'" "select-pane -l"


      # source: https://www.rockyourcode.com/copy-and-paste-in-tmux/
      ## Use vim keybindings in copy mode
      setw -g mode-keys vi
      set-option -s set-clipboard off
      unbind p
      bind p paste-buffer

      # copy to the paste buffer
      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi y send-keys -X rectangle-toggle
      unbind -T copy-mode-vi Enter

      # share tmux paste buffer to OS clipboard
      bind-key -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel 'wl-copy'
      bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel 'wl-copy'
    '';
  };

  # use Fish shell
  users.defaultUserShell = pkgs.fish;
  programs.fish.enable = true;

  environment.variables = {
    EDITOR="vim";
  };

  # tailscale everywhere by default
  services.tailscale.enable = true;
}


