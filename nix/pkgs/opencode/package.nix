{ stdenv }:

(builtins.getFlake "github:anomalyco/opencode/014614d35b397775e5d397a490fc72368c894ec2")
  .packages.${stdenv.hostPlatform.system}.opencode
