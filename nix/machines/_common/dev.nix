{ config, pkgs, pkgs-unstable, ... }:
{
  environment.systemPackages = with pkgs-unstable; [
    harlequin # SQL TUI
    hugo

    # agentic dev workflow tools
    aider-chat-full
    claude-code
    claude-code-router
    claude-monitor
    crush
    gemini-cli
    opencode
  ];
}
