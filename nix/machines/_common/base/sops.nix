{ config, lib, systems-secrets, ... }:
{
  sops = {
    age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

    # reference the <host>.yaml as the default secrets file
    defaultSopsFile =
      "${systems-secrets}/secrets/${config.networking.hostName}.yaml";

  };
}
