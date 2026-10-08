# Package a NixOS guest's disko image into a unified Incus VM image tarball
# (`metadata.yaml` + `rootfs.img`) for use with `incus image import` / the
# OpenTofu `incus_image` resource.
#
# Usage (flake): mkIncusImage self.nixosConfigurations."<vm>"
{ pkgs }:
cfg:
let
  hostName = cfg.config.networking.hostName;
  imageName = cfg.config.disko.devices.disk.main.imageName or hostName;
  qcow2 = "${cfg.config.system.build.diskoImages}/${imageName}.qcow2";
in
pkgs.runCommand "${hostName}-incus-image" {
  nativeBuildInputs = [ pkgs.qemu-utils pkgs.gnutar ];
} ''
  mkdir work
  # Compact/re-compress the disko qcow2 so dead clusters are dropped.
  qemu-img convert -c -O qcow2 ${qcow2} work/rootfs.img

  cat > work/metadata.yaml <<EOF
architecture: x86_64
creation_date: 1
properties:
  os: NixOS
  release: "25.11"
  description: "NixOS Incus image: ${hostName}"
EOF

  tar -C work -cf $out metadata.yaml rootfs.img
''