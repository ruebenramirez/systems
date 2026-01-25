{
  networking.wg-quick.interfaces = {
    wg1 = {
      configFile = "/persist/etc/wireguard/wgnet-mullvad.conf";
    };
  };
}
