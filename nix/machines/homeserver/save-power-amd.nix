{ config, pkgs, ... }:

{
  boot.kernelParams = [
    # AMD power management settings
    "amd_pstate=passive"
    "idle=nomwait"

    # Enable PCIe Active State Power Management (ASPM)
    "pcie_aspm=force"

    # SATA link power management aggressive mode
    "libata.force=noncq"
  ];

  # CPU frequency scaling governor set to powersave for AC
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "power";
      PLATFORM_PROFILE_ON_AC = "low-power";

      # Keep CPU boost enabled
      CPU_BOOST_ON_AC = 1;

      # Runtime power management for devices
      RUNTIME_PM_ON_AC = "auto";

      # USB autosuspend enabled
      USB_AUTOSUSPEND = 1;
      USB_AUTOSUSPEND_DISABLE_ON_SHUTDOWN = 0;
    };
  };

  # Disable power-profiles-daemon to avoid conflicts with TLP
  services.power-profiles-daemon.enable = false;

  # Disable thermald (Intel-specific)
  services.thermald.enable = false;

  # # Disable unused hardware via systemd
  # systemd.services.bluetooth.serviceConfig = {
  #   ExecStartPre = "/bin/systemctl mask bluetooth.service";
  #   ExecStart = "/bin/true";
  #   Type = "oneshot";
  #   RemainAfterExit = true;
  # };

  # Enable powertop auto-tuning at boot
  systemd.services.powertop-auto-tune = {
    description = "PowerTOP Auto Tune";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.powertop}/bin/powertop --auto-tune";
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # AMD GPU power management settings
  boot.loader.grub.extraConfig = ''
    amdgpu.dpm=1
  '';
}
