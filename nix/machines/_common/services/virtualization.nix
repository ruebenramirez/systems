{ config, pkgs, pkgs-unstable, ... }:
{
  # Enable KVM kernel modules
  boot.kernelModules = [ "kvm-intel" "kvm-amd" "tun" ];

  # Optional: Enable nested virtualization
  boot.extraModprobeConfig = ''
    options kvm_intel nested=1
    options kvm ignore_msrs=1
  '';

  # Enable libvirtd service
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
      ovmf = {
        enable = true;
        packages = [(pkgs.OVMF.override {
          secureBoot = true;
          tpmSupport = true;
        }).fd];
      };
    };
  };

  # Add required packages
  environment.systemPackages = with pkgs; [
    virt-manager    # For virt-install command
    libvirt         # For virsh command
    qemu_kvm        # QEMU with KVM support
    OVMF           # UEFI firmware
    dnsmasq        # For default libvirt network
    virt-viewer     # For console access (if GUI needed)
  ];

  # Add your user to libvirtd group
  users.users.rramirez = {
    extraGroups = [ "libvirtd" ];
  };

  # Configure networking for VMs
  networking.firewall = {
    # Allow libvirt bridge traffic
    trustedInterfaces = [ "virbr0" ];
  };

  # Enable default libvirt network
  systemd.services.libvirtd.postStart = ''
    sleep 2
    ${pkgs.libvirt}/bin/virsh net-list --all | grep -q default || \
    ${pkgs.libvirt}/bin/virsh net-define ${pkgs.writeText "default-network.xml" ''
      <network>
        <name>default</name>
        <uuid>9a05da11-e96b-47f3-8253-a3a482e445f5</uuid>
        <forward mode='nat'>
          <nat>
            <port start='1024' end='65535'/>
          </nat>
        </forward>
        <bridge name='virbr0' stp='on' delay='0'/>
        <mac address='52:54:00:0a:cd:21'/>
        <ip address='192.168.122.1' netmask='255.255.255.0'>
          <dhcp>
            <range start='192.168.122.2' end='192.168.122.254'/>
          </dhcp>
        </ip>
      </network>
    ''}
    ${pkgs.libvirt}/bin/virsh net-autostart default
    ${pkgs.libvirt}/bin/virsh net-start default || true
  '';
}
