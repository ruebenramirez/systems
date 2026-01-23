{
  networking.wg-quick.interfaces = {
    wg0 = {
      configFile = "/persist/etc/wireguard/wgnet.conf";
    };
  };
}
