# Declarative extensions for the pi coding agent.
#
# pi has no system-wide settings file, and ~/.pi/agent/settings.json is mutable
# per-user state (credentials, model preferences), so nothing here ever writes to
# it. pi auto-discovers extensions at ~/.pi/agent/extensions/<name>/index.ts,
# which needs no settings change, so each configured extension is symlinked there
# on every switch.
#
# Extensions are added by a module in this directory (see ./md-export.nix) or
# directly by a machine:
#
#     my.piExtensions.pi-md-export = pkgs.callPackage ../../../pkgs/pi-md-export/package.nix { };
#
# Each derivation must unpack to a directory holding index.ts plus its own
# node_modules, because pi resolves an extension's dependencies from the
# extension directory.
{ config, lib, ... }:

let
  cfg = config.my.piExtensions;

  normalUsers = lib.filterAttrs (_: u: u.isNormalUser or false) config.users.users;

  # pi's agent-directory extension auto-discovery path, per user.
  extensionsDir = home: lib.escapeShellArg "${home}/.pi/agent/extensions";

  # One `ln -sfn` per configured extension, keyed by attribute name so the
  # version in the derivation name does not leak into the path pi loads.
  extensionLinks = home: ''
    ${lib.concatStrings (lib.mapAttrsToList (linkName: drv: ''
      ln -sfn ${drv} ${extensionsDir home}/${linkName}
    '') cfg)}
  '';

  linkExtensions = name: u: ''
    if [ -d ${lib.escapeShellArg u.home} ]; then
      mkdir -p ${extensionsDir u.home}
      chown ${name}:${u.group or "users"} ${extensionsDir u.home}
    ${extensionLinks u.home}
    fi
  '';
in
{
  options.my.piExtensions = lib.mkOption {
    type = lib.types.attrsOf lib.types.package;
    default = { };
    description = ''
      pi coding agent extensions, symlinked into
      ~/.pi/agent/extensions/&lt;attr-name&gt;/ for every normal user.
    '';
  };

  config = lib.mkIf (cfg != { }) {
    system.activationScripts.pi-extensions = {
      deps = [
        "users"
        "groups"
      ];
      text = lib.concatStringsSep "\n" (lib.mapAttrsToList linkExtensions normalUsers);
    };
  };
}
