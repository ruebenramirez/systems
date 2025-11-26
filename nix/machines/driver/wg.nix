{
  networking.wg-quick.interfaces = {
    wg0 = {
      configFile = "/persist/etc/wireguard/wg0-wgnet.conf";
    };
    wg1 = {
      configFile = "/persist/etc/wireguard/wg1-mullvad.conf";
    };
  };
}
