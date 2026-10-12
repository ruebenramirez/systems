{ stdenv }:

(builtins.getFlake "github:anomalyco/opencode/733b2c627e5aec39cb33cc22373bdce33053ef2c")
  .packages.${stdenv.hostPlatform.system}.opencode
