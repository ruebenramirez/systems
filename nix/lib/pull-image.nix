# dockerTools.pullImage with retries: upstream runs skopeo exactly once, so a
# transient registry hiccup (nightly 178: codeberg.org `GET /v2/ EOF`) fails
# the whole system build. No upstream fix exists (checked master). Injected as
# the `pullImageWithRetry` module arg (see _common/base/default.nix).
pkgs:
args:
let
  image = pkgs.dockerTools.pullImage args;
in
image.overrideAttrs (
  old:
  {
    buildCommand = ''
      pull_image() {
      ${old.buildCommand}
      }
      attempt=1
      until pull_image; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt 5 ]; then
          echo "error: image pull failed after 5 attempts" >&2
          exit 1
        fi
        echo "warning: image pull failed; retrying ($attempt/5)" >&2
        rm -rf "$out"  # flat output: drop any partial tar before retrying
        sleep 5
      done
    '';
  }
)
