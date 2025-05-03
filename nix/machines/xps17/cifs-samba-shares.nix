
{ config, pkgs, ... }:

{


  # install Desktop packages
  environment.systemPackages = with pkgs; [
    samba4Full
  ];


  services.samba = {
    enable = true;
    securityType = "user";
    # Replace extraConfig with settings
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "NixOS Samba Server";
        "server role" = "standalone server";
        "map to guest" = "bad user";
        "dns proxy" = "no";
        "security" = "user";
      };
    };
    shares = {
      rueb = {
        path = "/tank/Shares/rueb";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "rramirez";  # Replace with your username
      };
      moni = {
        path = "/tank/Shares/moni";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "moni";  # Replace with your username
      };
      jellyfin-video = {
        path = "/tank/Video";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "rramirez";  # Replace with your username
      };
      jellyfin-music = {
        path = "/tank/Music";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "rramirez";  # Replace with your username
      };
    };
  };

  users.users.moni = {
    isNormalUser = true;
  };
}
