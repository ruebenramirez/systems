# Shared configuration for the pi coding agent: the agent itself, the
# declarative extension mechanism, and the extensions installed on every machine
# that imports this.
{ pkgs-unstable
, ...
}:
{
  imports = [
    ./extensions.nix
    ./md-export.nix
  ];

  environment.systemPackages = [
    pkgs-unstable.pi-coding-agent
  ];
}
