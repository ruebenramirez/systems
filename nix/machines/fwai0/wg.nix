{
  networking.wg-quick.interfaces = {
    wg0 = {
      configFile = "/persist/etc/wireguard/wg0-wgnet.conf";
    };
  };
}
