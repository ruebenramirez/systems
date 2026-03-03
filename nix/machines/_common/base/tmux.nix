{ config, pkgs, pkgs-unstable, ... }:
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
      set -g allow-passthrough on
      set -g default-terminal "tmux-256color"
      set -g status-bg colour40
      setw -g window-status-current-style bg=colour40

      # ── OSC52 fix for mosh compatibility ──
      # Tell tmux to emit OSC52 in a format mosh can parse.
      # %p1%.0s suppresses the selection-type parameter that mosh chokes on.
      set -ag terminal-overrides ",*:Ms=\\E]52;c%p1%.0s;%p2%s\\7"
      set -as terminal-features ",*:clipboard"
      set -s set-clipboard external

      # Bypass tmux's OSC52 path entirely by writing directly to client TTY.
      # This is the most reliable method for mosh sessions.
      bind -T copy-mode-vi y \
        send -X copy-pipe-and-cancel \
        "sh -c 'b64=\$(dd bs=1 count=100000 status=none | base64 | tr -d \"\n\"); printf \"\033]52;c;%s\a\" \"\$b64\" > \"\$1\"' sh #{client_tty}"
      bind -T copy-mode-vi Enter \
        send -X copy-pipe-and-cancel \
        "sh -c 'b64=\$(dd bs=1 count=100000 status=none | base64 | tr -d \"\n\"); printf \"\033]52;c;%s\a\" \"\$b64\" > \"\$1\"' sh #{client_tty}"
      bind -T copy-mode-vi MouseDragEnd1Pane \
        send -X copy-pipe-and-cancel \
        "sh -c 'b64=\$(dd bs=1 count=100000 status=none | base64 | tr -d \"\n\"); printf \"\033]52;c;%s\a\" \"\$b64\" > \"\$1\"' sh #{client_tty}"

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
