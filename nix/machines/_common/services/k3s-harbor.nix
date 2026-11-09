# Harbor, the fleet's pull-through container registry, deployed as a Helm
# release on the k3s cluster (issue #51).
#
# Harbor cannot be Nix-activated: nixpkgs has no Harbor server package and no
# NixOS service module, so the deployment is the upstream chart and the
# configuration below only says what the chart should install. What *is*
# declarative here is the chart pin, the values, the certificate, and the
# sops-managed credentials; what is declarative about Harbor's *content*
# (projects, proxy-cache endpoints, retention) lives in `tofu/harbor/`.
#
# Shape of the install:
#   - chart `harbor` from https://helm.goharbor.io, deployed by k3s' helm
#     controller in the `harbor` namespace -- the same mechanism
#     services/k3s-nfs-pvc.nix and services/k3s-monitoring.nix use.
#   - every PVC asks for my.k3sHarbor.storageClass, so registry data lands on
#     the homeserver tank (services/k3s-nfs-pvc.nix) and survives node loss.
#   - `harbor.rueb.dev` is served by k3s' Traefik over a Let's Encrypt
#     certificate issued the same way the monitoring UIs' is: DNS-01 through
#     Cloudflare, from one node, published into the cluster as a TLS Secret.
#
# Secrets: only two values are Harbor's own credentials in the sense that
# matters -- the admin password, and core's `secretKey`, which is what encrypts
# the upstream registry credentials Harbor stores (the Docker Hub token). Both
# come from sops and reach the chart through `existingSecret*`, never through
# chart values: chart values are rendered into the nix store and the k3s
# manifest directory, both world-readable.
#
# The internal Postgres password is the chart's own `harbor-database` Secret,
# which the seeding unit creates from sops before the chart renders in practice
# (the helm controller races it; the sync unit below covers the miss), with
# `database.internal.password = null`: the chart's default is the published
# literal "changeit", and its `lookup` helper only prefers the live Secret when
# the values entry is empty. On upgrades the lookup reads back the seeded value,
# so the chart re-renders the Secret unchanged and the two never drift.
#
# The internal Valkey is honestly unauthenticated: the chart hardcodes an empty
# password for `type: internal` (`harbor.redis.password`), so there is nothing
# to seed. It is reachable from any pod in the cluster (k3s runs
# --disable-network-policy), and it holds cache and job-queue data, not
# credentials.
{
  config,
  lib,
  pkgs,
  secretFile,
  ...
}:
let
  cfg = config.my.k3sHarbor;
  mirrors = import ../../../lib/registry-mirrors.nix;
  url = "https://${cfg.host}";
  issuesTls = cfg.tls.enable && config.networking.hostName == cfg.tls.issueOn;

  # Written by the seeding unit below, referenced by the chart above; one name
  # so the producer and the consumer cannot drift into a CreateContainerConfigError.
  fleetSecret = "harbor-fleet-secrets";

  # Requests are reservations, not limits: the sum here is what the scheduler
  # packs onto the cluster (~3 GiB of requests, ~6.5 GiB of limits) against the
  # ~16 GiB of request room the three 6 GiB nodes had unclaimed at bring-up. See
  # the sizing note in ../k3s-node.nix for why the nodes did not need growing.
  componentResources = {
    nginx = {
      requests = {
        cpu = "20m";
        memory = "128Mi";
      };
      limits.memory = "256Mi";
    };
    portal = {
      requests = {
        cpu = "25m";
        memory = "128Mi";
      };
      limits.memory = "256Mi";
    };
    core = {
      requests = {
        cpu = "100m";
        memory = "512Mi";
      };
      limits.memory = "1Gi";
    };
    jobservice = {
      requests = {
        cpu = "50m";
        memory = "256Mi";
      };
      limits.memory = "512Mi";
    };
    registry = {
      requests = {
        cpu = "50m";
        memory = "256Mi";
      };
      limits.memory = "1Gi";
    };
    # The registry pod runs two containers: the distribution itself and the
    # registryctl controller.
    registryController = {
      requests = {
        cpu = "25m";
        memory = "128Mi";
      };
      limits.memory = "256Mi";
    };
    database = {
      requests = {
        cpu = "100m";
        memory = "512Mi";
      };
      limits.memory = "1Gi";
    };
    redis = {
      requests = {
        cpu = "50m";
        memory = "256Mi";
      };
      limits.memory = "512Mi";
    };
    trivy = {
      requests = {
        cpu = "100m";
        memory = "768Mi";
      };
      limits.memory = "2Gi";
    };
    exporter = {
      requests = {
        cpu = "10m";
        memory = "64Mi";
      };
      limits.memory = "128Mi";
    };
  };

  # containerd mirror entries: `<registry>` pulls become
  # `<harbor>/<project>/<original path>`, which is Harbor's proxy-cache layout.
  # The rewrite runs on the repository path, so `library/nginx` becomes
  # `dockerhub/library/nginx`. The endpoint stays at the registry root on purpose:
  # containerd appends `/v2/<repo>` itself, so a path in the endpoint URL would
  # not be honoured the way a rewrite is.
  containerdMirrors = builtins.listToAttrs (
    map (m: {
      name = m.registry;
      value = {
        endpoint = [ url ];
        rewrite = {
          "^([^/].*)$" = "${m.project}/$1";
        };
      };
    }) cfg.containerdProxyProjects
  );

  registriesYaml = builtins.toJSON { mirrors = containerdMirrors; };
in
{
  options.my.k3sHarbor = {
    # Importing this module is the opt-in, as with the other k3s service modules.
    # Two things must already exist in systems-secrets or activation fails:
    # secrets/harbor-shared.yaml (see docs/harbor.md for the bootstrap order).
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Harbor, as a Helm release on this k3s cluster.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = mirrors.host;
      description = ''
        The registry's hostname. Like the monitoring UIs it is a Cloudflare A
        record pointing at the cluster's tailnet addresses, so it resolves only
        from inside the tailnet; the certificate is still a real ACME one,
        because DNS-01 does not need the name to be reachable.
      '';
    };

    namespace = lib.mkOption {
      type = lib.types.str;
      default = "harbor";
      description = "Namespace the chart is installed into; created by the seeding unit, not by the chart.";
    };

    storageClass = lib.mkOption {
      type = lib.types.str;
      default = "nfs";
      description = ''
        StorageClass for every PVC, named explicitly rather than left to the
        cluster default -- same reasoning as my.k3sMonitoring.storageClass.
      '';
    };

    chartVersion = lib.mkOption {
      type = lib.types.str;
      default = "1.19.4";
      description = "harbor-helm chart version (bundles Harbor 2.15.4).";
    };

    chartHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-dZhyu6uvBVJCaAlrnVUaSA0/aBTRPtCHIwNuJnOFkYI=";
      description = "Hash of the harbor chart tarball.";
    };

    dbImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/goharbor/harbor-db:v2.15.4";
      description = ''
        Image used by the Postgres bootstrap initContainer below. It reuses the
        chart's own database image so nothing extra has to be pulled; it has to
        be spelled out because chart values cannot reference other chart values,
        so it must be bumped alongside `chartVersion`.
      '';
    };

    persistence = lib.mkOption {
      type = lib.types.submodule {
        options = {
          registry = lib.mkOption {
            type = lib.types.str;
            default = "100Gi";
            description = ''
              Registry volume. Sparse on the tank: what counts is what GC and the
              proxy-cache retention keep, not this number.
            '';
          };
          database = lib.mkOption {
            type = lib.types.str;
            default = "10Gi";
          };
          jobLog = lib.mkOption {
            type = lib.types.str;
            default = "5Gi";
          };
          redis = lib.mkOption {
            type = lib.types.str;
            default = "5Gi";
          };
          trivyCache = lib.mkOption {
            type = lib.types.str;
            default = "10Gi";
            description = "Trivy vulnerability DB; it is a few GiB before any artifacts are scanned.";
          };
        };
      };
      default = { };
    };

    tls = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Serve the registry over TLS. A registry is the one service here
              where plain HTTP is not an option even on a tailnet: container
              clients refuse to negotiate against an insecure registry without
              being told to, per host.
            '';
          };

          certName = lib.mkOption {
            type = lib.types.str;
            default = "harbor-ui";
            description = "Name of the security.acme certificate on the issuing host.";
          };

          secretName = lib.mkOption {
            type = lib.types.str;
            default = "harbor-tls";
            description = "Name of the Kubernetes kubernetes.io/tls Secret the ingress uses.";
          };

          issueOn = lib.mkOption {
            type = lib.types.str;
            default = "k3s-1";
            description = ''
              Single server that asks ACME and publishes the certificate, for the
              same reason my.k3sMonitoring.tls.issueOn names one host: three
              renewals of one name would burn Let's Encrypt's duplicate allowance
              for no gain.
            '';
          };
        };
      };
      default = { };
    };

    containerdProxyProjects = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            registry = lib.mkOption {
              type = lib.types.str;
              description = "Upstream registry as it appears in image references, e.g. ghcr.io.";
            };
            project = lib.mkOption {
              type = lib.types.str;
              description = "Harbor proxy-cache project that fronts it; must exist in Harbor (tofu/harbor).";
            };
          };
        }
      );
      default = mirrors.projects;
      description = ''
        Upstreams rewritten through Harbor in every node's containerd config.
        Set to `[]` to leave containerd pointing straight at the upstreams.

        k3s keeps the original registry as containerd's last endpoint, so a
        Harbor outage falls back to a direct pull rather than failing the pull;
        that is what makes mirroring `docker.io` safe even though k3s' own
        system images (rancher/mirrored-*) come from Docker Hub too.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.tls.enable || cfg.tls.secretName != "";
        message = "my.k3sHarbor.tls.secretName must be set when TLS is enabled.";
      }
    ];

    sops.secrets.harbor-admin-password = secretFile "harbor-shared" // {
      mode = "0400";
      restartUnits = [ "harbor-secrets-sync.service" ];
    };
    sops.secrets.harbor-core-secret-key = secretFile "harbor-shared" // {
      mode = "0400";
      restartUnits = [ "harbor-secrets-sync.service" ];
    };
    sops.secrets.harbor-database-password = secretFile "harbor-shared" // {
      mode = "0400";
      restartUnits = [
        "harbor-secrets-sync.service"
        "harbor-database-password-sync.service"
      ];
    };

    services.k3s.autoDeployCharts.harbor = {
      repo = "https://helm.goharbor.io";
      name = "harbor";
      version = cfg.chartVersion;
      hash = cfg.chartHash;
      targetNamespace = cfg.namespace;

      # The seeding unit creates `harbor-database` before the chart renders, and
      # the chart templates a Secret of that same name, so without this the
      # install fails on "resource already exists" -- helm only adopts a resource
      # it does not already own with --take-ownership.
      extraFieldDefinitions.spec.takeOwnership = true;

      values = {
        expose = {
          type = "ingress";
          tls = {
            enabled = cfg.tls.enable;
            certSource = "secret";
            secret.secretName = cfg.tls.secretName;
          };
          ingress = {
            hosts.core = cfg.host;
            className = "traefik";
            controller = "default";
            # No body-size annotation: Traefik applies no request-body limit
            # unless one is configured, so image layers of any size pass through
            # it, and the chart's own nginx-flavoured annotations are inert here.
          };
        };

        # What Harbor tells clients to dial, and what the token service hands
        # back to docker/podman. Must match the name clients use, or pushes get
        # redirected somewhere they cannot reach.
        externalURL = url;

        existingSecretAdminPassword = fleetSecret;
        existingSecretAdminPasswordKey = "HARBOR_ADMIN_PASSWORD";
        existingSecretSecretKey = fleetSecret;

        # Every Harbor volume is ReadWriteOnce on the NFS provisioner, so a
        # RollingUpdate would schedule the new pod before the old one released
        # its volume and the new one would sit Pending on an attached PV.
        updateStrategy.type = "Recreate";

        logLevel = "info";

        persistence = {
          enabled = true;
          # Deleting a PVC must not delete the last copy of the registry's bytes.
          resourcePolicy = "keep";
          persistentVolumeClaim = {
            registry = {
              storageClass = cfg.storageClass;
              size = cfg.persistence.registry;
            };
            jobservice.jobLog = {
              storageClass = cfg.storageClass;
              size = cfg.persistence.jobLog;
            };
            database = {
              storageClass = cfg.storageClass;
              size = cfg.persistence.database;
            };
            redis = {
              storageClass = cfg.storageClass;
              size = cfg.persistence.redis;
            };
            trivy = {
              storageClass = cfg.storageClass;
              size = cfg.persistence.trivyCache;
            };
          };
          imageChartStorage = {
            disableredirect = false;
            type = "filesystem";
            filesystem.rootdirectory = "/storage";
          };
        };

        nginx.resources = componentResources.nginx;
        portal.resources = componentResources.portal;
        core.resources = componentResources.core;
        jobservice.resources = componentResources.jobservice;
        registry.registry.resources = componentResources.registry;
        registry.controller.resources = componentResources.registryController;
        # trivy is the one component whose template renders `resources`
        # unconditionally, so leaving it unset renders `null`.
        trivy.resources = componentResources.trivy;
        exporter.resources = componentResources.exporter;
        database.internal.resources = componentResources.database;
        # The chart's default is the published literal "changeit" and its
        # `lookup` helper only prefers the live Secret when the values entry is
        # empty, so null here makes the chart render the password the seeding
        # unit put into the `harbor-database` Secret -- not a generated one.
        database.internal.password = null;
        # The chart's own `data-permissions-ensurer` runs
        # `chmod -R 700 /var/lib/postgresql/data/pgdata || true`. On a
        # brand-new volume `pgdata` does not exist yet, so it no-ops, and
        # Postgres then creates `pgdata/pg18` inheriting the group-write that
        # kubelet's `fsGroup` put on the volume -- which Postgres refuses to
        # serve ("data directory ... has invalid permissions"). That failure is
        # permanent rather than transient: the half-written data directory makes
        # the image skip its own first-boot init on every retry, so the
        # `registry` database is never created and core crash-loops on it
        # forever. Creating the directory at 0700 first gives the ensurer
        # something to fix and gives `pg18` a clean parent. The chart's own
        # comment says it added the ensurer for this on "some CSIs e.g. Ceph";
        # the NFS provisioner hits it the same way. Note the value key is
        # misspelled upstream and must be spelled this way to be read at all.
        database.internal.extrInitContainers = [
          {
            name = "create-pgdata";
            image = cfg.dbImage;
            imagePullPolicy = "IfNotPresent";
            command = [
              "/bin/sh"
              "-c"
              "mkdir -p /var/lib/postgresql/data/pgdata && chmod 700 /var/lib/postgresql/data/pgdata"
            ];
            securityContext = {
              runAsUser = 999;
              runAsNonRoot = true;
              allowPrivilegeEscalation = false;
            };
            volumeMounts = [
              {
                name = "database-data";
                mountPath = "/var/lib/postgresql/data";
              }
            ];
          }
        ];
        redis.internal.resources = componentResources.redis;

        # kube-prometheus-stack selects ServiceMonitors in every namespace with
        # no label requirement (my.k3sMonitoring), so this is scraped without any
        # further wiring. It assumes the ServiceMonitor CRD already exists: true
        # today, and on a from-scratch cluster the install can fail once before
        # kube-prometheus-stack's CRDs land and the helm controller retries.
        metrics.enabled = true;
        metrics.serviceMonitor.enabled = true;
        metrics.serviceMonitor.interval = "1m";
      };
    };

    # containerd's registry mirror config. k3s reads this file at startup and
    # renders containerd's hosts.toml from it, so a change needs a k3s restart
    # -- which the trigger below asks for. That restarts the control plane and
    # everything in it, including Harbor; it is rare, and Recreate pods are the
    # chart's own update strategy anyway.
    environment.etc."rancher/k3s/registries.yaml" = lib.mkIf (cfg.containerdProxyProjects != [ ]) {
      text = registriesYaml;
    };
    systemd.services.k3s.restartTriggers = lib.mkIf (cfg.containerdProxyProjects != [ ]) [
      registriesYaml
    ];

    # Harbor's own credentials, and the namespace they live in, have to exist
    # before the chart renders: `existingSecret*` is a reference, and a missing
    # Secret means a pod stuck in CreateContainerConfigError rather than a
    # visible failure. Same sops -> Kubernetes bridge as the monitoring stack's
    # seeding unit, run on every server so whichever node is up converges it.
    systemd.services.harbor-secrets-sync = {
      description = "Seed Harbor's Kubernetes Secrets from this host's sops secrets";
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
        for _ in $(seq 1 60); do
          if kubectl get namespace default >/dev/null 2>&1; then break; fi
          sleep 5
        done
        kubectl create namespace ${cfg.namespace} --dry-run=client -o yaml | kubectl apply -f -
        # `secretKey` is the literal key name the chart requires: it is the
        # cipher key for credentials Harbor stores in its database.
        kubectl -n ${cfg.namespace} create secret generic ${fleetSecret} \
          --from-file=HARBOR_ADMIN_PASSWORD=/run/secrets/harbor-admin-password \
          --from-file=secretKey=/run/secrets/harbor-core-secret-key \
          --dry-run=client -o yaml | kubectl apply -f -
        # The chart's own database Secret, created before the chart renders so
        # its `lookup` finds it: with `database.internal.password = null` the
        # chart renders exactly this value, and keeps rendering it on upgrades.
        # The name is the chart's `harbor.fullname` + "-database" (release name
        # `harbor`, no nameOverride). Created only when absent: the Secret is
        # the record of what the *role* currently holds, and
        # harbor-database-password-sync below owns rotations -- overwriting it
        # here first would erase the old value the ALTER needs to authenticate.
        if ! kubectl -n ${cfg.namespace} get secret harbor-database >/dev/null 2>&1; then
          kubectl -n ${cfg.namespace} create secret generic harbor-database \
            --from-file=POSTGRES_PASSWORD=/run/secrets/harbor-database-password
        fi
      '';
    };

    # Postgres reads POSTGRES_PASSWORD only when it initialises its data
    # directory: if the volume already holds a cluster, the env value is
    # ignored, and the chart's `lookup` keeps whatever Secret was live at the
    # first install. So the Secret alone cannot converge a changed password --
    # same lesson as grafana-admin-sync in services/k3s-monitoring.nix. This
    # unit pushes the sops value into the running database and back into the
    # Secret, so a rotation converges without a wipe.
    systemd.services.harbor-database-password-sync = {
      description = "Converge Harbor's internal Postgres password on the sops-managed value";
      after = [ "harbor-secrets-sync.service" ];
      wants = [ "harbor-secrets-sync.service" ];
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

        want=$(cat /run/secrets/harbor-database-password)
        have=$(kubectl -n ${cfg.namespace} get secret harbor-database \
          -o jsonpath='{.data.POSTGRES_PASSWORD}' 2>/dev/null | base64 -d || true)

        # Repair a blank Secret before anything is asked to be healthy. If the
        # helm controller renders before the seeding unit, `lookup` finds
        # nothing, `password = null` renders empty, and postgres refuses to
        # start at all on a blank POSTGRES_PASSWORD. Neither the seeding unit
        # (guard: create only if absent -- and the chart made one) nor a later
        # activation fixes that, because the chart's `default` keeps
        # re-deriving empty from the present-but-blank key. Writing the real
        # value here lets the crashlooping pod initialise on its next restart.
        if [ -z "$have" ]; then
          kubectl -n ${cfg.namespace} create secret generic harbor-database \
            --from-file=POSTGRES_PASSWORD=/run/secrets/harbor-database-password \
            --dry-run=client -o yaml | kubectl apply -f -
          echo "harbor database Secret was blank; re-seeded from sops"
          exit 0
        fi

        if [ "$want" = "$have" ]; then
          echo "harbor database password already converged"
          exit 0
        fi

        # A real rotation. The chart is deployed by k3s' helm controller, so the
        # database may legitimately not exist yet when this runs; fifteen minutes
        # covers a slow first install without hanging the boot.
        if ! kubectl -n ${cfg.namespace} wait --for=condition=available \
             --timeout=15m statefulset/harbor-database >/dev/null 2>&1; then
          echo "harbor-database is not available; password was not converged" >&2
          exit 1
        fi

        # ALTER ROLE, not a re-init: the running pod's env keeps the old value,
        # but every client authenticates against the role, so the change takes
        # effect for new connections immediately. Connect over TCP with the
        # current Secret value (host auth is password-based -- core connects the
        # same way), and hand the new value to psql as a variable so quoting is
        # psql's job, not the shell's. The chart's next helm upgrade re-renders
        # the Secret from the live value (the `lookup` helper), so the two stay
        # converged.
        if ! echo "ALTER ROLE postgres WITH PASSWORD :'pw';" |
          kubectl -n ${cfg.namespace} exec -i statefulset/harbor-database -c database -- \
            env PGPASSWORD="$have" psql -h 127.0.0.1 -U postgres -q -v pw="$want"; then
          echo "postgres rejected the password change (Secret and role may have drifted)" >&2
          exit 1
        fi
        kubectl -n ${cfg.namespace} create secret generic harbor-database \
          --from-file=POSTGRES_PASSWORD=/run/secrets/harbor-database-password \
          --dry-run=client -o yaml | kubectl apply -f -
        echo "harbor database password converged on the sops value"
      '';
    };

    security.acme = lib.mkIf issuesTls {
      acceptTerms = true;
      defaults.email = "postmaster@rueb.dev";

      certs.${cfg.tls.certName} = {
        domain = cfg.host;
        dnsProvider = "cloudflare";
        credentialFiles = {
          CLOUDFLARE_DNS_API_TOKEN_FILE = config.sops.secrets.cloudflare-token.path;
        };
        reloadServices = [ "harbor-tls-sync.service" ];
      };
    };

    sops.secrets.cloudflare-token = lib.mkIf issuesTls (
      secretFile "cloudflare-dns-client" // { mode = "0400"; }
    );

    systemd.services.harbor-tls-sync = lib.mkIf issuesTls {
      description = "Publish the Harbor registry certificate into the cluster";
      after = [
        "k3s.service"
        "harbor-secrets-sync.service"
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
        for _ in $(seq 1 24); do
          if kubectl -n ${cfg.namespace} get configmap >/dev/null 2>&1; then break; fi
          sleep 5
        done
        kubectl -n ${cfg.namespace} create secret tls ${cfg.tls.secretName} \
          --cert="$cert" --key="$key" \
          --dry-run=client -o yaml | kubectl apply -f -
      '';
    };
  };
}
