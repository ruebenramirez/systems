{ pkgs, pkgs-unstable, ... }:

let
  opencode = pkgs.callPackage ../../pkgs/opencode/package.nix { };
in
{
  imports = [
    # pi coding agent + its declarative extensions (see ./pi/default.nix)
    ./pi/default.nix
  ];

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
  ];

  # OpenRouter API key, consumed by agent tooling (CodeCompanion, etc.) to
  # reach hosted models such as deepseek/deepseek-v4.1-flash.
  sops.secrets.openrouter-api-key = {
    owner = "rramirez";
    group = "users";
    mode = "0440";
  };
}
