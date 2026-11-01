# k3s server role for the cluster VMs: HA embedded-etcd control plane, joined
# over the tailnet, with the cluster token from sops.
#
# Importing this module is how a machine says "I am a k3s server". The first
# server initialises the etcd cluster (`my.k3sCluster.clusterInit = true`); the
# others join it through `my.k3sCluster.firstServer`.
{
  config,
  lib,
  pkgs,
  secretFile,
  tailnet,
  ...
}:
let
  cfg = config.my.k3sCluster;
  isFirst = cfg.clusterInit;
  serverHost = tailnet.host cfg.firstServer;
in
{
  options.my.k3sCluster = {
    # Importing this module is the opt-in (same convention as
    # ../monitoring.nix). The one ordering rule it does not enforce: the cluster
    # token must already exist in systems-secrets, or k3s crash-loops on boot.
    # Seed the secret first -- docs/monitoring.md has the bootstrap order.
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "This host as a k3s server in the fleet cluster.";
    };

    clusterInit = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Initialise the embedded-etcd cluster from this host. Exactly one server
        sets this; the rest join through my.k3sCluster.firstServer.
      '';
    };

    firstServer = lib.mkOption {
      type = lib.types.str;
      default = "k3s-1";
      description = "Host that owns cluster initialisation; the join address is derived from it.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !isFirst -> config.networking.hostName != cfg.firstServer;
        message = ''
          my.k3sCluster.firstServer is "${cfg.firstServer}" and that is this host,
          but clusterInit is false: this server would join itself. Either set
          my.k3sCluster.clusterInit = true here or point firstServer at the
          server that owns the cluster.
        '';
      }
      {
        assertion = isFirst -> config.networking.hostName == cfg.firstServer;
        message = ''
          my.k3sCluster.clusterInit is true on ${config.networking.hostName}, but
          firstServer is "${cfg.firstServer}". Only the first server may
          initialise the etcd cluster; two initialisations make two clusters.
        '';
      }
    ];

    sops.secrets.k3s-cluster-token = secretFile "k3s-shared" // {
      # k3s reads the token as root; nothing else needs it.
      mode = "0400";
    };

    services.k3s = {
      enable = true;
      role = "server";
      clusterInit = isFirst;
      serverAddr = lib.optionalString (!isFirst) "https://${serverHost}:6443";
      tokenFile = config.sops.secrets.k3s-cluster-token.path;

      # local-path would put PVCs on the node's own disk, which is exactly what
      # the cluster must not do: VM roots are disposable and per-node, so data
      # written there is invisible to every other node and gone on a rebuild.
      # Dynamic provisioning comes from my.k3sNfsPvc instead.
      disable = [ "local-storage" ];

      # Pods must reach each other across nodes; flannel's VXLAN and the kubelet
      # ports have to be open between the servers.
      extraFlags = [
        "--flannel-backend=vxlan"
        "--disable-network-policy"
        # The join URL is a tailnet FQDN, so the serving cert has to name it --
        # k3s only puts the node name/IP, `kubernetes` and `localhost` in by
        # default, and a joining server rejects the cert otherwise.
        "--tls-san"
        serverHost
        "--tls-san"
        (tailnet.host config.networking.hostName)
      ];

      # Pods resolve `<host>.tailnet.rueb.dev` through the cluster DNS, which
      # otherwise only knows upstream (public) DNS -- and the fleet scrapes,
      # probes and joins by tailnet name. k3s imports `/etc/coredns/custom/*.server`
      # as extra server blocks, so this ConfigMap hands the tailnet zone to
      # Tailscale's MagicDNS (100.100.100.100), which is reachable from pods
      # through the node. Nothing else goes through this resolver: public names
      # keep using the node's upstream.
      manifests."tailnet-dns".content = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          name = "coredns-custom";
          namespace = "kube-system";
        };
        data."tailnet.server" = ''
          ${tailnet.domain}:53 {
              errors
              cache 30
              forward . 100.100.100.100
          }
        '';
      };
    };

    # k3s assumes these; without them flannel/Kube-proxy silently fail to route.
    boot.kernelModules = [
      "br_netfilter"
      "overlay"
      "nf_conntrack"
    ];
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
    };

    # NFS is the PVC backend (my.k3sNfsPvc) and the node's own data share.
    boot.supportedFilesystems = [ "nfs" ];

    networking.firewall = {
      # Cluster plumbing between the servers: API, etcd, flannel VXLAN, kubelet.
      # 9090 because Prometheus runs in the host network (see k3s-monitoring): the
      # API server's proxy and every other node's pod traffic reach it at the
      # node address, so it is a cluster port like the others here.
      allowedTCPPorts = [
        6443
        2379
        2380
        9090
        10250
      ];
      allowedUDPPorts = [ 8472 ];
      # Anything on the tailnet is an authenticated fleet member; the API and
      # the LoadBalancer services (status page, Grafana) listen here.
      interfaces.tailscale0.allowedTCPPorts = [
        80
        443
        6443
      ];
    };

    environment.systemPackages = [
      pkgs.kubernetes-helm
      pkgs.kubectl
    ];

    # kubectl for root without hunting for the kubeconfig.
    environment.shellAliases = {
      k = "k3s kubectl";
    };
    environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  };
}
