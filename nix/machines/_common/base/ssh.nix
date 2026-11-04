{
  services.openssh = {

    enable = true;

    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      # sshd's two concurrency ceilings, both of which a deploy runs into: it
      # multiplexes many channels over one connection to the builder and the
      # target, and CI overlaps with whatever else is sshing in.
      #
      # MaxStartups refuses connections sitting in the preauth phase -- the
      # default 10:30:100 starts refusing at random past 10 -- and nix calls that
      # `failed to start SSH connection to '<host>'`.
      #
      # MaxSessions caps channels on a single connection at 10; past it ssh fails
      # the session and nix reads the failure as a broken handshake,
      # `'nix-store --serve' protocol mismatch from '<host>', got 'started'`.
      # Reproduced exactly at the limit: 16 parallel channels over one connection
      # give 10 successes and 6 of those errors.
      MaxStartups = "100:30:200";
      MaxSessions = 64;
    };

    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persist/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  programs.ssh.extraConfig = ''
    Host *
      ServerAliveInterval 15
      ServerAliveCountMax 3
  '';

}
