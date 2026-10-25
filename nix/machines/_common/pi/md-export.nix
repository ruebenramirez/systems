# /md — export the current pi session as a Markdown transcript, which pi's
# built-in /export cannot do (it only writes HTML and JSONL).
#
# Pulls in the extension itself from nix/pkgs/pi-md-export and hands it to the
# linking mechanism in ./extensions.nix (imported alongside this module by
# ./default.nix).
#
# Nothing extra goes into systemPackages for it: node already arrives with
# ../base/editor.nix (language servers), and the extension's one dependency
# (@mariozechner/clipboard) ships a prebuilt napi-rs binary that links against
# nothing but glibc. The clipboard half of /md still needs a display server, so
# over SSH or on a headless guest only the "save to file" path works; files land
# in ~/.pi/agent/pi-sessions-extracted/.
{ pkgs, ... }:

{
  my.piExtensions.pi-md-export = pkgs.callPackage ../../../pkgs/pi-md-export/package.nix { };
}
