{ config, pkgs, pkgs-unstable, ... }:

let
  opencode = pkgs.callPackage ../../pkgs/opencode/package.nix { };
in
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
    pkgs-unstable.ccusage
    pkgs-unstable.codex
    pkgs-unstable.goose-cli
    opencode
    pkgs-unstable.pi-coding-agent
  ];
}
