{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  mpv,
}:

buildGoModule rec {
  pname = "pine";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "Thelost77";
    repo = "pine";
    rev = "v${version}";
    hash = "sha256-2Ji7PWpkMBUz7KEPwq5+vys4lzMVzeHwPWNQ4DGozJg=";
  };

  vendorHash = "sha256-ljXBI88V6+bM9zIFIvnjZnJ+D9Oo4hqRFYgchI7fgyU=";

  nativeBuildInputs = [
    makeWrapper
  ];

  postInstall = ''
    wrapProgram "$out/bin/pine" \
      --prefix PATH : ${lib.makeBinPath [ mpv ]}
  '';

  meta = {
    description = "Terminal UI for Audiobookshelf";
    homepage = "https://github.com/Thelost77/pine";
    license = lib.licenses.mit;
    mainProgram = "pine";
    platforms = lib.platforms.linux;
  };
}
