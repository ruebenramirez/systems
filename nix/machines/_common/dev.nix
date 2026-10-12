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

  # Bearer auth for the OpenAI-compatible endpoint on the tailnet. This unit is
  # not DynamicUser, so owner-matching is reliable.
  sops.secrets.llama-cpp-api-key = {
    owner = "rramirez";
    group = "users";
    mode = "0440";
  };

}
