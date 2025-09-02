{ config, pkgs, pkgs-unstable, ... }:

let

in
{

  environment.systemPackages = with pkgs; [
    tmux
  ];

  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [
      yank
      vim-tmux-navigator
    ];
    extraConfig = ''
      set -g set-clipboard on
      set -g default-terminal "tmux-256color"
      set -g status-bg colour40
      setw -g window-status-current-style bg=colour40

      # osc52 sequence override (fix copy from mosh sessions)
      #   source: https://gist.github.com/yudai/95b20e3da66df1b066531997f982b57b
      set-option -ag terminal-overrides ",xterm-256color:Ms=\\E]52;c;%p2%s\\7"

      # navigate next and prev tmux tabs
      bind -n S-left  prev
      bind -n S-right next

      # switch active pane w/ vim keys
      bind j select-pane -D
      bind k select-pane -U
      bind h select-pane -L
      bind l select-pane -R

      # vim-tmux-navigator plugin configuration
      # use Ctrl + vim keys to move between vim and tmux panes
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


      # Use vim keybindings in copy mode
      set-window-option -g mode-keys vi
      unbind p
      bind p paste-buffer
    '';
  };
}
