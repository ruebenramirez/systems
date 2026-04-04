{ config, pkgs, pkgs-unstable, ... }:
{
  environment.systemPackages = with pkgs; [
    harlequin # SQL TUI
    hugo

    # agentic dev workflow tools
    aider-chat-full
    claude-code
    claude-code-router
    claude-monitor
    crush
    pkgs-unstable.gemini-cli
    opencode
  ];
}
