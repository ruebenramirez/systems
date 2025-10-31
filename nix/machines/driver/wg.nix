{
  networking.wg-quick.interfaces = {
    # the interface arbitrarily.
    wg0 = {
      configFile = "/persist/etc/wireguard/wgnet.conf";
    };
    wg1 = {
      configFile = "/persist/etc/wireguard/mullvad.conf";
    };
  };
}
