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
    pkgs-unstable.codex
    pkgs-unstable.gemini-cli
    pkgs-unstable.goose-cli
    pkgs-unstable.opencode
  ];
}
