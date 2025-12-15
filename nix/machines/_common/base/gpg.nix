{ config, pkgs, ... }:

{

  environment = {
    systemPackages = with pkgs; [
      # hardware key
      gnupg
      pcsclite
      pinentry-curses
    ];
  };

  # part of gnupg reqs
  services.pcscd.enable = true;
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    # pinentryFlavor = "tty";
    # Make pinentry across multiple terminal windows, seamlessly
    enableSSHSupport = true;
  };

}
