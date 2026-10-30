{ config, lib, pkgs, pkgs-unstable, secretFile, ... }:

let
  opencode = pkgs.callPackage ../../pkgs/opencode/package.nix { };
in
{
  imports = [
    # pi coding agent + its declarative extensions (see ./pi/default.nix)
    ./pi/default.nix
  ];

  # OpenRouter API key, consumed by agent tooling (CodeCompanion, etc.) to reach
  # models such as deepseek/deepseek-v4.1-flash.
  #
  # The file is an option because the credential is per-tenant, not per-role: the
  # CI runner gets its own key so its jobs cannot spend the personal one.
  options.my.openrouterFile = lib.mkOption {
    type = lib.types.str;
    default = "openrouter-client";
    description = "systems-secrets file holding this machine's OpenRouter API key.";
  };

  config = {
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
      # pkgs-unstable.codex
      # pkgs-unstable.goose-cli
      opencode
    ];

    # The path stays /run/secrets/openrouter-api-key for every consumer (see
    # _common/base/editor.nix); only the file it is unwrapped from changes.
    sops.secrets.openrouter-api-key = secretFile config.my.openrouterFile // {
      owner = "rramirez";
      group = "users";
      mode = "0440";
    };
  };
}
