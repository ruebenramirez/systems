
{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    samba4Full
  ];

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "NixOS Samba Server";
        "server role" = "standalone server";
        "map to guest" = "bad user";
        "dns proxy" = "no";
        "security" = "user";
      };
      rueb = {
        path = "/tank/Shares/rueb";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "rramirez";
      };
      moni = {
        path = "/tank/Shares/moni";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0644";
        "directory mask" = "0755";
        "force user" = "moni";
      };
    };
  };

  users.users.moni = {
    isNormalUser = true;
  };
}
