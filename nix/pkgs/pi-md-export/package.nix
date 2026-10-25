# pi-md-export — `/md` slash command for the pi coding agent.
#
# Exports the current pi session to a readable Markdown transcript. Shipped as
# an npm pi package, but it is just one TypeScript extension file plus a single
# runtime dependency, so it is vendored here from the npm registry instead of
# being installed with `pi install npm:pi-md-export` (which would mutate
# ~/.pi/agent/settings.json and run npm at install time).
#
# Layout of $out is what pi's agent-directory extension discovery expects:
#   <dir>/index.ts                                  the extension entry point
#   <dir>/node_modules/@mariozechner/clipboard/     its one runtime dependency
# Linking that directory into ~/.pi/agent/extensions/ makes pi load it with no
# settings change. See nix/machines/_common/pi/extensions.nix.
{
  lib,
  nodejs,
  stdenvNoCC,
  fetchzip,
}:

let
  version = "0.4.2";
  clipboardVersion = "0.3.9";

  src = fetchzip {
    url = "https://registry.npmjs.org/pi-md-export/-/pi-md-export-${version}.tgz";
    hash = "sha256-7VhgkLHpdrfDMd//T06BBEtGm4XYZBikw3m8B8/+m00=";
  };

  # Pure-JS napi-rs loader; picks the platform .node binary at require() time.
  clipboard = fetchzip {
    url = "https://registry.npmjs.org/@mariozechner/clipboard/-/clipboard-${clipboardVersion}.tgz";
    hash = "sha256-pxPWL2TLqI9w0qBMLgAdb5+1BnNdECXXEPmtIHUWcGo=";
  };

  # Prebuilt napi-rs binaries, keyed by Nix system. They link only against glibc
  # (libc/libm/libpthread/libgcc_s), so nothing else is needed at runtime.
  nativeBindings = {
    "x86_64-linux" = {
      suffix = "linux-x64-gnu";
      src = fetchzip {
        url = "https://registry.npmjs.org/@mariozechner/clipboard-linux-x64-gnu/-/clipboard-linux-x64-gnu-${clipboardVersion}.tgz";
        hash = "sha256-O4g2m2klkWcaP6+fQk5RsRezB27AmTVt9XnFEcEDWAQ=";
      };
    };
    "aarch64-linux" = {
      suffix = "linux-arm64-gnu";
      src = fetchzip {
        url = "https://registry.npmjs.org/@mariozechner/clipboard-linux-arm64-gnu/-/clipboard-linux-arm64-gnu-${clipboardVersion}.tgz";
        hash = "sha256-mR3z+vRxk0UTY5zgnku3jBQYNOw+FTzOI7nmXJNtVZQ=";
      };
    };
  };

  nativeBinding =
    nativeBindings.${stdenvNoCC.hostPlatform.system}
    or (throw "pi-md-export: no prebuilt @mariozechner/clipboard binary for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "pi-md-export";
  inherit version src;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ nodejs ];

  installPhase = ''
    runHook preInstall

    clipboardDir="$out/node_modules/@mariozechner/clipboard"
    mkdir -p "$clipboardDir"

    # pi discovers ~/.pi/agent/extensions/<name>/index.ts, so the extension
    # entry point is installed under that name. Unmodified upstream source.
    cp extensions/md.ts "$out/index.ts"
    cp README.md LICENSE package.json "$out/"

    cp ${clipboard}/index.js ${clipboard}/index.d.ts \
      ${clipboard}/package.json "$clipboardDir/"
    cp ${nativeBinding.src}/clipboard.${nativeBinding.suffix}.node "$clipboardDir/"

    chmod -R u+w "$out"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    # The extension statically imports the clipboard binding, so a binding that
    # fails to load would break the whole extension at startup. Load it the way
    # pi will: from the extension directory, via node_modules resolution.
    cd "$out"
    node -e '
      const c = require("@mariozechner/clipboard");
      for (const fn of ["setText", "getText", "clear"]) {
        if (typeof c[fn] !== "function") { throw new Error("missing " + fn); }
      }
    '
  '';

  meta = {
    description = "pi coding agent extension that exports the session as Markdown";
    homepage = "https://github.com/w-winter/dot314";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
