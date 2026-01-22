{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    harlequin # SQL TUI
    hugo

    # agentic dev workflow tools
    aider-chat-full
    crush
    opencode

    # model handling
    llama-cpp-rocm # model file manipulation
    #llama-cpp-vulkan
    python3Packages.huggingface-hub # for huggingface-cli
  ];
}
