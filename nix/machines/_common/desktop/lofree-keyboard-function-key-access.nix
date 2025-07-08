{ config, pkgs, ... }:

let

in
{
  boot.extraModprobeConfig = ''
    # Lofree Flow84 keyboard function key fix
    # fnmode=2 enables standard F1-F12 function keys by default
    # Media functions accessible via Fn + F1-F12
    options hid_apple fnmode=2
  '';

}
