# The monitoring stack, declared as k3s auto-deployed addons on every server.
#
# One module, three moving parts:
#   - kube-prometheus-stack (Helm chart, pinned by hash) -- operator, Prometheus,
#     Alertmanager, Grafana and the Kubernetes alert rules.
#   - generated manifests -- blackbox exporter, Gatus status page, dashboards.
#   - scrape config + alert rules generated from nix/lib/inventory.nix.
#
# Everything the fleet monitors outside the cluster (the other nine hosts) is
# scraped by static config from that same inventory, so "what do we monitor" has
# exactly one answer in this repo.
{
  config,
  lib,
  pkgs,
  secretFile,
  tailnet,
  ...
}:
let
  cfg = config.my.k3sMonitoring;
  inventory = import ../../../lib/inventory.nix;
  stack = import ../monitoring-stack/prometheus.nix { inherit inventory; };
  dashboards = import ../monitoring-stack/dashboards.nix { inherit inventory; };

  urls = lib.mapAttrs (_: host: "${scheme}://${host}") cfg.hosts;

  scheme = if cfg.tls.enable then "https" else "http";

  # One mail description, two consumers: Alertmanager's global SMTP settings and
  # Gatus' own alerting block. Both deliver to the same mailbox by different
  # routes on purpose -- if one path breaks, the other still pages.
  mail = {
    from = "alertmanager@rueb.dev";
    to = cfg.alertEmail;
    smtpHost = "${tailnet.host "homeserver"}:25";
    smtpHostAddr = tailnet.host "homeserver";
    # Stalwart rejects a bare hostname ("550 Invalid EHLO domain"), so the HELO
    # has to be a real FQDN -- same constraint homeserver/srv/alerting.nix notes.
    heloDomain = cfg.hosts.alertmanager;
  };

  stackManifests = import ../monitoring-stack/manifests.nix {
    inherit
      inventory
      mail
      urls
      ;
    inherit (cfg) images hosts storageClass;
    tls = {
      hosts = builtins.attrValues cfg.hosts;
      secretName = cfg.tls.secretName;
    };
  };
in
{
  options.my.k3sMonitoring = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "The fleet monitoring stack on this k3s cluster.";
    };

    alertEmail = lib.mkOption {
      type = lib.types.str;
      default = "r3v2@rueb.dev";
      description = "Where Alertmanager and Gatus send mail.";
    };

    storageClass = lib.mkOption {
      type = lib.types.str;
      default = "nfs";
      description = ''
        StorageClass every PVC in the stack asks for. my.k3sNfsPvc creates it on
        the tank export; it is named explicitly instead of relying on the cluster
        default so the two installs cannot race each other.
      '';
    };

    hosts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        grafana = "monitoring.rueb.dev";
        alertmanager = "alerts.rueb.dev";
        status = "status.rueb.dev";
      };
      description = ''
        Tailnet-only hostnames of the stack's own UIs, served through k3s'
        Traefik ingress on the nodes' tailnet addresses -- they survive a node
        loss without a VIP because every node answers. The records themselves are
        created out of band as Cloudflare A records pointing at the cluster's
        tailnet IPs, which are unreachable from outside the tailnet; see
        docs/monitoring.md.
      '';
    };

    retention = lib.mkOption {
      type = lib.types.str;
      default = "14d";
      description = "Prometheus retention. Volume-sized, not aspiration-sized.";
    };

    retentionSize = lib.mkOption {
      type = lib.types.str;
      default = "18GiB";
      description = "Hard cap on the Prometheus TSDB so retention cannot outgrow its PVC.";
    };

    images = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        blackbox = "quay.io/prometheus/blackbox-exporter:v0.29.1";
        gatus = "ghcr.io/twin/gatus:v5.38.0";
      };
      description = "Pinned images for the generated manifests.";
    };

    chartVersion = lib.mkOption {
      type = lib.types.str;
      default = "92.17.0";
    };

    chartHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-8meYm+gxjxKzcnOgdVBNSYaip0Q4Pa98ygcyqNNdQA0=";
      description = "Hash of the kube-prometheus-stack chart tarball.";
    };

    tls = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Serve the stack's UIs over TLS. Not optional in practice: `.dev` is
              on the HSTS preload list, so a browser will not attempt plain HTTP
              for these names at all.
            '';
          };

          certName = lib.mkOption {
            type = lib.types.str;
            default = "monitoring-ui";
            description = ''
              Name of the security.acme certificate on the issuing host. It is a
              SAN certificate covering every name in my.k3sMonitoring.hosts, so
              one renewal covers all three UIs.
            '';
          };

          secretName = lib.mkOption {
            type = lib.types.str;
            default = "monitoring-ui-tls";
            description = "Name of the Kubernetes kubernetes.io/tls Secret the ingress uses.";
          };

          issueOn = lib.mkOption {
            type = lib.types.str;
            default = "k3s-1";
            description = ''
              Hostname of the single server that asks ACME for the certificate and
              publishes it into the cluster. One issuer on purpose: three servers
              renewing the same name would triple the requests against Let's
              Encrypt's duplicate-certificate allowance for no gain, since the
              secret is readable from every node.
            '';
          };
        };
      };
      default = { };
      description = "TLS for the monitoring UIs.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Grafana's admin credentials come from sops like everything else, and land
    # in the cluster through the seeding unit below rather than through Helm
    # values (chart values end up world-readable in the nix store).
    sops.secrets.grafana-admin-password = secretFile "monitoring-shared" // {
      mode = "0400";
      restartUnits = [ "k3s-cluster-secrets.service" ];
    };

    # Bearer token for the exit-node status-page tile (Gatus external
    # endpoint). download-vm-xps sends it with each push; Gatus validates it.
    # Same sops file as the exit node's own copy, so the two can never drift.
    sops.secrets.gatus-exit-node-token = secretFile "exit-node-monitor" // {
      mode = "0400";
      restartUnits = [ "k3s-cluster-secrets.service" ];
    };

    services.k3s = {
      # The k3s manifest submodule takes attrs (or lists of them) and renders
      # the YAML itself, so these stay structured data rather than strings.
      manifests = {
        "monitoring-namespace".content = stackManifests.namespace;
        "blackbox-exporter".content = stackManifests.blackbox;
        "gatus".content = stackManifests.gatus;
        "monitoring-ingress".content = stackManifests.ingresses;
      }
      // (builtins.listToAttrs (
        map (cm: {
          name = "grafana-dash-${cm.metadata.name}";
          value = {
            content = cm;
          };
        }) dashboards
      ));

      autoDeployCharts."kube-prometheus-stack" = {
        repo = "https://prometheus-community.github.io/helm-charts";
        name = "kube-prometheus-stack";
        version = cfg.chartVersion;
        hash = cfg.chartHash;
        targetNamespace = "monitoring";
        createNamespace = true;

        values = {
          # Name the class on every PVC the chart makes rather than relying on
          # the cluster default: the default annotation is applied by a chart in
          # another namespace, and ordering between the two installs is not
          # something this file should have to trust.
          global.storageClass = cfg.storageClass;

          # Every node already runs the fleet node_exporter (nix/machines/_common/
          # monitoring.nix), scraped by inventory over the tailnet. A second
          # exporter per node in a DaemonSet would duplicate it, give two answers
          # to "what is this host's disk doing", and fail to bind port 9100.
          # The subchart is gated on `nodeExporter.enabled`, not its own name.
          nodeExporter.enabled = false;
          "prometheus-node-exporter".enabled = false;
          "prometheus-windows-exporter".enabled = false;

          # k3s runs the control-plane components in one process with their
          # metrics bound to the node's loopback, so cluster pods cannot reach
          # them. Scraping what is reachable beats alerting on a target that can
          # never exist; apiserver, kubelet and CoreDNS are reachable.
          kubeEtcd.enabled = false;
          kubeScheduler.enabled = false;
          kubeControllerManager.enabled = false;
          kubeProxy.enabled = false;
          defaultRules.rules = {
            etcd = false;
            kubeSchedulerAlerting = false;
            kubeSchedulerRecording = false;
            kubeControllerManager = false;
            kubeProxy = false;
            # Written for the chart's own node-exporter job, which is off above;
            # the fleet-host rules in the inventory cover the same failures.
            nodeExporterAlerting = false;
            nodeExporterRecording = false;
          };

          additionalPrometheusRulesMap.fleet-rules = stack.rules;

          prometheus = {
            service.type = "ClusterIP";
            prometheusSpec = {
              inherit (cfg) retention retentionSize;
              scrapeInterval = "30s";
              evaluationInterval = "30s";
              additionalScrapeConfigs = stack.scrapeConfigs;
              # The node it runs on is a scrape target like every other host, and
              # a pod cannot fetch its own node's tailnet address -- the reply
              # path dies in the overlay. In the host namespace it can.
              hostNetwork = true;
              dnsPolicy = "ClusterFirstWithHostNet";
              storage.volumeClaimTemplate.spec = {
                accessModes = [ "ReadWriteOnce" ];
                storageClassName = cfg.storageClass;
                resources.requests.storage = "20Gi";
              };
              resources = {
                requests = {
                  cpu = "200m";
                  memory = "1Gi";
                };
                limits.memory = "2500Mi";
              };
              # A single Prometheus with an RWO volume cannot be replicated.
              replicas = 1;
              serviceMonitorNamespaceSelector = { };
              serviceMonitorSelector = { };
              podMonitorNamespaceSelector = { };
              podMonitorSelector = { };
              ruleNamespaceSelector = { };
              ruleSelector = { };
            };
          };

          alertmanager = {
            enabled = true;
            config = stack.alertmanagerConfig mail;
            service = {
              type = "ClusterIP";
              port = 9093;
            };
            alertmanagerSpec = {
              replicas = 1;
              storage.volumeClaimTemplate.spec = {
                accessModes = [ "ReadWriteOnce" ];
                storageClassName = cfg.storageClass;
                resources.requests.storage = "2Gi";
              };
              resources = {
                requests = {
                  cpu = "20m";
                  memory = "96Mi";
                };
                limits.memory = "256Mi";
              };
            };
          };

          grafana = {
            enabled = true;
            admin = {
              existingSecret = "grafana-admin";
              userKey = "admin-user";
              passwordKey = "admin-password";
            };
            service = {
              type = "ClusterIP";
              port = 80;
            };
            persistence.enabled = true;
            persistence.size = "5Gi";
            grafana.ini = {
              server = {
                root_url = urls.grafana;
                # Grafana sits behind k3s' LoadBalancer, which does not terminate
                # TLS; keep it plain-HTTP and tailnet-only rather than half-TLS.
                protocol = "http";
              };
              users.allow_sign_up = false;
              auth.anonymous.enable = false;
              analytics = {
                reporting_enabled = false;
                check_for_updates = false;
              };
            };
            sidecar = {
              dashboards.searchNamespace = "monitoring";
            };
          };
        };
      };
    };

    # sops -> Kubernetes Secret bridge. sops-nix puts the value on the host at
    # /run/secrets; Kubernetes needs it as a Secret object. Running it on every
    # server keeps the cluster convergent whichever node is leader, and sops'
    # restartUnits re-runs it when the value rotates.
    # TLS for the UIs, issued the same way homeserver issues `*.rueb.dev`
    # (docs/monitoring.md): NixOS' ACME client with a Cloudflare DNS-01 challenge.
    # DNS-01 is the only challenge that works here -- the certificates are for
    # names that resolve to tailnet addresses, which Let's Encrypt cannot reach.
    #
    # Only one node issues; the certificate is handed to Traefik as a TLS Secret
    # in the monitoring namespace by the unit below, which ACME restarts on each
    # renewal.
    security.acme = lib.mkIf (cfg.tls.enable && config.networking.hostName == cfg.tls.issueOn) {
      acceptTerms = true;
      defaults.email = "postmaster@rueb.dev";

      certs.${cfg.tls.certName} = {
        domain = builtins.head (builtins.attrValues cfg.hosts);
        extraDomainNames = builtins.tail (builtins.attrValues cfg.hosts);
        dnsProvider = "cloudflare";
        credentialFiles = {
          CLOUDFLARE_DNS_API_TOKEN_FILE = config.sops.secrets.cloudflare-token.path;
        };
        reloadServices = [ "monitoring-ui-tls-sync.service" ];
      };
    };

    sops.secrets.cloudflare-token = lib.mkIf (
      cfg.tls.enable && config.networking.hostName == cfg.tls.issueOn
    ) (secretFile "cloudflare-dns-client" // { mode = "0400"; });

    systemd.services.monitoring-ui-tls-sync =
      lib.mkIf (cfg.tls.enable && config.networking.hostName == cfg.tls.issueOn)
        {
          description = "Publish the monitoring UI certificate into the cluster";
          after = [
            "k3s.service"
            "k3s-cluster-secrets.service"
            "acme-${cfg.tls.certName}.service"
          ];
          wants = [ "k3s.service" ];
          wantedBy = [ "multi-user.target" ];
          path = [
            config.services.k3s.package
            pkgs.kubectl
            pkgs.coreutils
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -euo pipefail
            export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
            cert=/var/lib/acme/${cfg.tls.certName}/fullchain.pem
            key=/var/lib/acme/${cfg.tls.certName}/key.pem
            # A renewal can fire before the API has anything to say to us; the cert is
            # good for 60 days, so waiting a minute here costs nothing.
            for _ in $(seq 1 24); do
              if kubectl -n monitoring get configmap >/dev/null 2>&1; then break; fi
              sleep 5
            done
            kubectl -n monitoring create secret tls ${cfg.tls.secretName} \
              --cert="$cert" --key="$key" \
              --dry-run=client -o yaml | kubectl apply -f -
          '';
        };

    systemd.services.k3s-cluster-secrets = {
      description = "Seed Kubernetes Secrets from this host's sops secrets";
      after = [
        "k3s.service"
        "sops-install-secrets.service"
      ];
      wants = [ "k3s.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        config.services.k3s.package
        pkgs.kubectl
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
        # k3s is systemd-notified, but the API can still be a few seconds from
        # answering after activation; the loop is cheaper than a failed unit.
        for _ in $(seq 1 60); do
          if kubectl get namespace default >/dev/null 2>&1; then break; fi
          sleep 5
        done
        kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
        kubectl -n monitoring create secret generic grafana-admin \
          --from-literal=admin-user=admin \
          --from-file=admin-password=/run/secrets/grafana-admin-password \
          --dry-run=client -o yaml | kubectl apply -f -
        kubectl -n monitoring create secret generic gatus-exit-node-token \
          --from-file=token=/run/secrets/gatus-exit-node-token \
          --dry-run=client -o yaml | kubectl apply -f -
      '';
    };

    # Grafana keeps the admin password in its own database, and only adopts the
    # value from the environment (or the chart's `admin.existingSecret`) when it
    # creates that database. Pointing the chart at the `grafana-admin` Secret is
    # therefore not enough: if the database exists before the Secret does -- which
    # is what happens on a first install, because the chart deploys minutes after
    # the seeding unit runs -- Grafana initializes with a generated password and
    # the seeded one is silently ignored. That is not a hypothetical: the admin
    # login on this stack was unusable until this unit existed.
    #
    # So the Secret is only the transport; the password is pushed into the running
    # database here. Grafana's own CLI is the only supported way to do it, and it
    # runs inside the container because the image has no shell and the database is
    # on the pod's volume.
    systemd.services.grafana-admin-sync = {
      description = "Converge Grafana's admin password on the sops-managed value";
      after = [ "k3s-cluster-secrets.service" ];
      wants = [ "k3s-cluster-secrets.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        config.services.k3s.package
        pkgs.kubectl
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -uo pipefail
        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

        # The chart is deployed by k3s' helm controller, so Grafana may legitimately
        # not exist yet when this runs. Fifteen minutes covers a slow first install
        # without hanging the boot.
        if ! kubectl -n monitoring wait --for=condition=available \
             --timeout=15m deploy/kube-prometheus-stack-grafana >/dev/null 2>&1; then
          echo "grafana is not available; admin password was not converged" >&2
          exit 1
        fi

        password=$(kubectl -n monitoring get secret grafana-admin \
          -o jsonpath='{.data.admin-password}' | base64 -d)

        # `--homepath` is required: the CLI otherwise looks for its database under
        # /usr/share/grafana/data instead of the mounted volume.
        # Idempotent -- resetting to the current value is a no-op write.
        if ! kubectl -n monitoring exec deploy/kube-prometheus-stack-grafana -c grafana -- \
             /usr/share/grafana/bin/grafana cli \
               --homepath /usr/share/grafana \
               --config /etc/grafana/grafana.ini \
               admin reset-admin-password "$password" >/dev/null 2>&1; then
          echo "grafana rejected the password reset" >&2
          exit 1
        fi
        echo "grafana admin password converged on the sops value"
      '';
    };
  };
}
