{ config, pkgs, pkgs-unstable, ... }:
{
  environment.systemPackages = with pkgs; [
    harlequin # SQL TUI
    hugo

    # agentic dev workflow tools
    aider-chat-full
    ansible
    ansible-lint
    awscli2
    awsls
    awslogs
    aws-gate
    # claude-code
    # claude-monitor
    pkgs-unstable.codex
    pkgs-unstable.goose-cli
    pkgs-unstable.opencode
    pkgs-unstable.pi-coding-agent
  ];
}
