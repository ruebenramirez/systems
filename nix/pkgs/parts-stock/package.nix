# parts-stock -- "Inventory Check", an offline-first barcode-scanning inventory
# PWA (https://github.com/shabdroop/parts-stock). Upstream has no build step:
# the PWA *is* the source tree, and its own docs describe serving these files
# from a static web server as the deployment.
#
# Upstream is NOT self-contained: index.html loads papaparse, xlsx and jsQR
# from jsdelivr, app.js defaults the parts list to raw.githubusercontent, and
# upstream's service worker precaches CDN URLs. This package vendors the three
# libraries and patches the references at install time, so the served site has
# zero external references and the PWA needs no network once loaded.
#
# server.py is deliberately not packaged. It is the optional Flask "admin
# server" that uploads and re-serves the parts CSV, and its /api/upload and
# /api/delete are unauthenticated -- nothing should serve that publicly. The
# frontend does not need it: the Setup tab imports a CSV directly or fetches
# one by URL, and $out/data/parts.csv is a URL on the same origin.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
}:

let
  version = "unstable-2026-10-25";

  src = fetchFromGitHub {
    owner = "shabdroop";
    repo = "parts-stock";
    rev = "99ff009e964e3ec39ea5bb5c28d4bd7b7469352a";
    hash = "sha256-RIehyyCvQUNpnCMBkbVWvxVi/TmpflKjSvFmf8hJTyE=";
  };

  # The same files upstream loads from jsdelivr, pinned by content hash.
  vendor = {
    "papaparse.min.js" = fetchurl {
      url = "https://cdn.jsdelivr.net/npm/papaparse@5.4.1/papaparse.min.js";
      hash = "sha256-uOhwxdKyl3LxDJ+pppPIuJaqyFQO1nAePMYwTGg/69s=";
    };
    "xlsx.full.min.js" = fetchurl {
      url = "https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js";
      hash = "sha256-yVBhl8r4CaB1tt7h2g02+xnacVj/6KiOewyWxdhiPJk=";
    };
    "jsQR.js" = fetchurl {
      url = "https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.js";
      hash = "sha256-vEDIoVGWI2sjFNsIVvcsoLSZgM1UE7jIUqc0n1/uCFk=";
    };
  };
in
stdenvNoCC.mkDerivation {
  pname = "parts-stock";
  inherit version src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/vendor"
    cp index.html manifest.json app.js "$out/"
    cp -r data "$out/data"
    chmod -R u+w "$out"

    cp ${vendor."papaparse.min.js"} "$out/vendor/papaparse.min.js"
    cp ${vendor."xlsx.full.min.js"} "$out/vendor/xlsx.full.min.js"
    cp ${vendor."jsQR.js"} "$out/vendor/jsQR.js"
    chmod u+w "$out"/vendor/*

    # Point the CDN <script> tags and the GitHub-raw parts URL at same-origin
    # copies, then swap in a service worker that precaches the whole bundle.
    substituteInPlace "$out/index.html" \
      --replace-fail 'https://cdn.jsdelivr.net/npm/papaparse@5.4.1/papaparse.min.js' '/vendor/papaparse.min.js' \
      --replace-fail 'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js' '/vendor/xlsx.full.min.js' \
      --replace-fail 'https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.js' '/vendor/jsQR.js' \
      --replace-fail 'https://raw.githubusercontent.com/shabdroop/parts-stock/master/data/parts.csv' '/data/parts.csv' \
      --replace-fail 'Downloads the latest parts list published on GitHub' 'Loads the parts list served from this host'

    substituteInPlace "$out/app.js" \
      --replace-fail 'https://raw.githubusercontent.com/shabdroop/parts-stock/master/data/parts.csv' '/data/parts.csv'

    cp ${./service-worker.js} "$out/service-worker.js"
    chmod u+w "$out/service-worker.js"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    # nginx serves $out directly, so anything missing here is a 404 in the
    # browser: index.html and app.js are referenced by name, service-worker.js
    # is registered by app.js, and manifest.json is what makes it installable.
    for f in index.html app.js manifest.json service-worker.js \
             data/parts.csv \
             vendor/papaparse.min.js vendor/xlsx.full.min.js vendor/jsQR.js; do
      [ -s "$out/$f" ] || { echo "no $f in the built web root" >&2; exit 1; }
    done

    # The point of the vendoring: nothing the browser loads may reach off-host.
    # manifest.json is exempt -- its only URL is the SVG xmlns namespace,
    # which is never fetched.
    if grep -rEoh 'https?://[^" )]*' "$out/index.html" "$out/app.js" "$out/service-worker.js"; then
      echo "external URLs left in the web root (above)" >&2
      exit 1
    fi
  '';

  meta = {
    description = "Offline-first barcode-scanning inventory PWA";
    homepage = "https://github.com/shabdroop/parts-stock";
    # Upstream ships no LICENSE file, so there is nothing to name here.
    # Vendored libs are MIT (papaparse, jsQR) and Apache-2.0 (SheetJS 0.18.5).
    license = lib.licenses.unfreeRedistributable;
    sourceProvenance = [ lib.sourceTypes.structuredSource ];
  };
}
