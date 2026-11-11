# Plain Kubernetes manifests for the monitoring stack, generated from the fleet
# inventory and auto-deployed by k3s. kube-prometheus-stack itself arrives as a
# Helm chart (see ../services/k3s-monitoring.nix); what is here is the part that
# is cheaper to write than to chart: the blackbox exporter whose probes the
# inventory defines, the status page whose endpoints the inventory defines, and
# the namespace both live in.
{
  inventory,
  lib,
  urls,
  mail,
  images,
  storageClass,
  hosts,
  tls,
}:
let
  ns = "monitoring";

  labelPart = "fleet-monitoring";

  labels = {
    "app.kubernetes.io/part-of" = labelPart;
    "app.kubernetes.io/managed-by" = "systems-flake";
  };

  # ---- blackbox exporter -------------------------------------------------
  # Stateless: Prometheus drives every probe, so the only config is the module
  # definitions the inventory's probes name.
  #
  # These config bodies are serialised with `builtins.toJSON`, not a generated
  # YAML file: `yaml.generate` returns a derivation, and reading it forces a
  # *build during evaluation* -- which fails on any host evaluating without a
  # builder (the PR check runs `nix eval` with builds disabled). JSON is a
  # subset of YAML 1.2, and both consumers load their config through Go's
  # yaml parser, so the documents are still ordinary YAML to them.
  blackboxConfigText = builtins.toJSON {
    modules = inventory.blackboxModules;
  };

  blackbox = [
    {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "blackbox-exporter";
        namespace = ns;
        labels = labels // {
          "app.kubernetes.io/name" = "blackbox-exporter";
        };
      };
      data = {
        "blackbox.yml" = blackboxConfigText;
      };
    }
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "blackbox-exporter";
        namespace = ns;
        labels = labels // {
          "app.kubernetes.io/name" = "blackbox-exporter";
        };
      };
      spec = {
        replicas = 1;
        selector = {
          matchLabels = {
            "app.kubernetes.io/name" = "blackbox-exporter";
          };
        };
        template = {
          metadata = {
            labels = labels // {
              "app.kubernetes.io/name" = "blackbox-exporter";
            };
            # Neither exporter reloads its config from the mounted ConfigMap on
            # its own, so the hash rides along in the pod template: editing the
            # inventory rolls the pod instead of leaving a stale exporter.
            annotations."checksum/config" = builtins.hashString "sha256" blackboxConfigText;
          };
          spec = {
            containers = [
              {
                name = "blackbox-exporter";
                image = images.blackbox;
                args = [
                  "--config.file=/config/blackbox.yml"
                  "--web.listen-address=:9110"
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = 9110;
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/-/healthy";
                    port = "http";
                  };
                  initialDelaySeconds = 10;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/-/healthy";
                    port = "http";
                  };
                };
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "64Mi";
                  };
                  limits = {
                    memory = "128Mi";
                  };
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities = {
                    drop = [ "ALL" ];
                    # ICMP probes would need NET_RAW; every inventory probe is
                    # TCP/HTTP/TLS today, so nothing asks for it.
                    add = [ ];
                  };
                  runAsNonRoot = true;
                  runAsUser = 65534;
                };
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/config";
                    readOnly = true;
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "config";
                configMap = {
                  name = "blackbox-exporter";
                };
              }
            ];
          };
        };
      };
    }
    {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "blackbox-exporter";
        namespace = ns;
        labels = labels // {
          "app.kubernetes.io/name" = "blackbox-exporter";
        };
      };
      spec = {
        selector = {
          "app.kubernetes.io/name" = "blackbox-exporter";
        };
        ports = [
          {
            name = "http";
            port = 9110;
            targetPort = "http";
          }
        ];
      };
    }
  ];

  # ---- Gatus status page --------------------------------------------------
  # Gatus probes independently of Prometheus: both read the same inventory, so
  # the alert path and the status page can never disagree about the fleet.
  gatusEndpoint =
    s:
    let
      host = s.host;
      grafanaLink = path: params: {
        url = "${urls.grafana}${path}?${params}";
        label = "Grafana";
      };
      links = [
        (grafanaLink "/d/fleet-host-health/fleet-host-health" "var-host=${host}")
        (grafanaLink "/d/fleet-service-probes/fleet-service-probes" "var-service=${
          builtins.replaceStrings [ "-" ] [ "_" ] s.name
        }")
      ];
      common = {
        name = s.title;
        group = s.group;
        interval = "2m";
        alerts = [
          {
            type = "email";
            failure-threshold = 2;
            success-threshold = 2;
          }
        ];
        inherit links;
      };
    in
    if s.probe.module == "http" then
      common
      // {
        url = s.probe.target;
        conditions = [
          "[STATUS] == 200"
          "[RESPONSE_TIME] < 3000"
          # TLS is only a certificate question where TLS is involved.
        ]
        ++ (
          if builtins.substring 0 8 s.probe.target == "https://" then
            [ "[CERTIFICATE_EXPIRATION] > 120h" ]
          else
            [ ]
        );
      }
    else
      # Gatus derives the probe type from the URL scheme -- there is no `type`
      # key -- so non-HTTP services get a scheme-appropriate URL and a
      # connectivity condition. Protocol handshake depth stays blackbox's job;
      # here the question a green tile answers is "does the port speak".
      let
        scheme =
          {
            tcp = "tcp://";
            imap = "tls://";
          }
          .${s.probe.module};
      in
      common
      // {
        url = scheme + s.probe.target;
        conditions = [
          "[CONNECTED] == true"
        ]
        ++ (if s.probe.module == "imap" then [ "[CERTIFICATE_EXPIRATION] > 120h" ] else [ ]);
      };

  gatusConfig = {
    debug = false;
    web = {
      address = "0.0.0.0";
      port = 8080;
      metrics = true;
    };
    ui = {
      title = "rueb.dev fleet status";
      "dark-theme" = true;
      header = "Fleet";
      "back-url" = urls.grafana;
      "back-title" = "Grafana";
    };
    storage = {
      type = "sqlite";
      path = "/data/gatus.db";
    };
    "remote-timeout" = "15s";
    # Push-based tiles (inventory.pushStatusEndpoints): Gatus cannot probe
    # "is the exit node's egress Mullvad" -- only the node itself can answer --
    # so the node writes the answer to its textfile collector, Prometheus reads
    # it, and the job below POSTs the verdict here. Gatus marks the tile DOWN
    # when pushes stop (heartbeat) as well as when they report failure.
    # Gatus runs os.ExpandEnv over its config before parsing, so the token
    # rides in as a Secret-backed env var rather than sitting in the ConfigMap;
    # it only grants writing this one tile's status.
    external-endpoints = map (e: {
      name = e.name;
      group = e.group;
      token = "\${GATUS_EXIT_NODE_TOKEN}";
      heartbeat.interval = e.heartbeat;
      alerts = [
        {
          type = "email";
          failure-threshold = 2;
          success-threshold = 2;
        }
      ];
    }) inventory.pushStatusEndpoints;
    alerting = {
      email = {
        from = mail.from;
        to = mail.to;
        host = mail.smtpHostAddr;
        port = 25;
        # Stalwart's MX listener does not advertise STARTTLS on the tailnet and
        # the traffic never leaves the network, so plaintext is deliberate.
        starttls = false;
        "html-content" = false;
      };
    };
    endpoints = map gatusEndpoint inventory.statusServices;
  };

  gatusConfigText = builtins.toJSON gatusConfig;

  gatus = [
    {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "gatus-config";
        namespace = ns;
        labels = labels // {
          "app.kubernetes.io/name" = "gatus";
        };
      };
      data = {
        "config.yaml" = gatusConfigText;
      };
    }
    {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "gatus-data";
        namespace = ns;
        labels = labels // {
          "app.kubernetes.io/name" = "gatus";
        };
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = storageClass;
        resources.requests.storage = "1Gi";
      };
    }
    {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "gatus";
        namespace = ns;
        labels = labels // {
          "app.kubernetes.io/name" = "gatus";
        };
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector = {
          matchLabels = {
            "app.kubernetes.io/name" = "gatus";
          };
        };
        template = {
          metadata = {
            labels = labels // {
              "app.kubernetes.io/name" = "gatus";
            };
            annotations."checksum/config" = builtins.hashString "sha256" gatusConfigText;
          };
          spec = {
            containers = [
              {
                name = "gatus";
                image = images.gatus;
                env = [
                  {
                    name = "GATUS_CONFIG_PATH";
                    value = "/config";
                  }
                  # Expanded into the external-endpoint token at config load.
                  # Seeded from sops by k3s-cluster-secrets; check-sops-secrets
                  # gates the sops side in CI and the seeding unit converges at
                  # activation. optional: true so an unseeded Secret cannot
                  # block the Pod from starting -- one missing secret must not
                  # blackhole the whole status page (issue #89 review).
                  {
                    name = "GATUS_EXIT_NODE_TOKEN";
                    valueFrom.secretKeyRef = {
                      name = "gatus-exit-node-token";
                      key = "token";
                      optional = true;
                    };
                  }
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = 8080;
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = "http";
                  };
                  initialDelaySeconds = 15;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/health";
                    port = "http";
                  };
                };
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "64Mi";
                  };
                  limits = {
                    memory = "256Mi";
                  };
                };
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/config";
                    readOnly = true;
                  }
                  {
                    name = "data";
                    mountPath = "/data";
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "config";
                configMap = {
                  name = "gatus-config";
                };
              }
              {
                name = "data";
                persistentVolumeClaim = {
                  claimName = "gatus-data";
                };
              }
            ];
          };
        };
      };
    }
    {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "gatus";
        namespace = ns;
        labels = labels // {
          "app.kubernetes.io/name" = "gatus";
        };
      };
      spec = {
        selector = {
          "app.kubernetes.io/name" = "gatus";
        };
        ports = [
          {
            name = "http";
            port = 80;
            targetPort = "http";
          }
        ];
      };
    }
    {
      # Monitor the monitor: Gatus' own page is scraped by Prometheus so its
      # silence is an alert too.
      apiVersion = "monitoring.coreos.com/v1";
      kind = "ServiceMonitor";
      metadata = {
        name = "gatus";
        namespace = ns;
        labels = labels;
      };
      spec = {
        selector.matchLabels = {
          "app.kubernetes.io/name" = "gatus";
        };
        endpoints = [
          {
            port = "http";
            path = "/metrics";
            interval = "60s";
          }
        ];
      };
    }
  ];

  # ---- push-based status tile -------------------------------------------
  # The exit node cannot push its own status tile: the tailnet policy grants
  # `tag:exit` nothing outbound, so the node may receive from any peer but can
  # never dial one -- a node-side POST to status.rueb.dev goes out `tailscale0`
  # and is dropped by the peer's filter with no reply at all (issue #90). So
  # the direction is inverted: Prometheus already scrapes the node inbound,
  # and this job reads those series back out of Prometheus and POSTs the
  # verdict to Gatus over cluster DNS. Nothing on the tailnet gains outbound
  # access, and a collector that stops writing starves the tile instead of
  # freezing it green.
  #
  # Today there is exactly one push tile and its checks are exit-node-specific,
  # so the job is written for that one tile; the key comes from the inventory so
  # the tile and the pusher cannot drift apart.
  exitNodePushTile = builtins.head inventory.pushStatusEndpoints;

  # Gatus's endpoint key is `<group>_<name>`, lowercase, spaces as underscores.
  exitNodePushKey =
    lib.toLower (builtins.replaceStrings [ " " ] [ "_" ] "${exitNodePushTile.group}_${exitNodePushTile.name}");

  # A healthy sample is at most one collector interval plus one scrape old
  # (60s + 30s); 180s is three missed collector ticks, which is what "stale"
  # has to mean before it is a real outage rather than a slow run.
  exitNodePushStaleAfter = "180";

  exitNodePushScript = ''
    set -eu

    prom=$PROM_URL
    gatus=$GATUS_URL
    key=$EXIT_NODE_KEY
    stale_after=$STALE_AFTER_SECONDS
    # A literal $ in a Nix indented string is two single quotes before it; `$$`
    # is no escape -- Nix emits it and bash reads the PID (issue #90 item 1).
    token=''${GATUS_EXIT_NODE_TOKEN:-}

    reason=""

    fail() {
      if [ -z "$reason" ]; then
        reason="$1"
      else
        reason="$reason,$1"
      fi
    }

    # Each check is an instant query whose result vector is non-empty exactly
    # when the check passes: `min(<gauge>) == 1` drops the series when the
    # gauge reads 0 *or* when it is gone entirely (host down, collector dead,
    # series expired), so absence is the failure and there is no JSON to parse.
    passes() {
      curl -fsS -m 10 -G --data-urlencode "query=$1" "$prom/api/v1/query" 2>/dev/null \
        | grep -q '"result":\[{'
    }

    if ! curl -fsS -m 10 "$prom/-/ready" >/dev/null 2>&1; then
      # Fail closed: an unreadable Prometheus is never reported as a healthy
      # exit node, and naming it beats labelling the outage as a leak.
      fail prometheus-unreachable
    else
      if ! passes 'min(exit_node_egress_is_mullvad) == 1'; then
        fail egress-not-via-wg1
      fi
      if ! passes 'min(exit_node_route_fix_present) == 1'; then
        fail route-fix-missing
      fi
      if ! passes 'min(exit_node_fwmark_route_ok) == 1'; then
        fail fwmark-stranded
      fi
      if ! passes "time() - min(exit_node_metrics_timestamp_seconds) < $stale_after"; then
        fail collector-stale
      fi
    fi

    if [ -z "$token" ]; then
      echo 'exit-node-status-push: GATUS_EXIT_NODE_TOKEN is empty; cannot push' >&2
      exit 1
    fi

    if [ -z "$reason" ]; then
      query='success=true'
    else
      # Gatus shows this on the tile; keep it URL-safe.
      safe=$(printf '%s' "$reason" | tr -c 'A-Za-z0-9._-' '_')
      query="success=false&error=$safe"
    fi

    code=$(curl -sS -o /dev/null -w '%{http_code}' -m 10 -X POST \
      -H "Authorization: Bearer $token" \
      "$gatus/api/v1/endpoints/$key/external?$query" 2>/dev/null || echo no-response)

    if [ "$code" != 200 ]; then
      echo "exit-node-status-push: gatus returned $code" >&2
      exit 1
    fi
  '';

  exitNodeStatusPush = [
    {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "exit-node-status-push";
        namespace = ns;
        labels = labels // {
          "app.kubernetes.io/name" = "exit-node-status-push";
        };
      };
      data = {
        "push.sh" = exitNodePushScript;
      };
    }
    {
      apiVersion = "batch/v1";
      kind = "CronJob";
      metadata = {
        name = "exit-node-status-push";
        namespace = ns;
        labels = labels // {
          "app.kubernetes.io/name" = "exit-node-status-push";
        };
      };
      spec = {
        # Well inside the tile's heartbeat, so the tile only goes DOWN once the
        # pusher has failed several times over, not on one missed minute.
        schedule = "* * * * *";
        concurrencyPolicy = "Forbid";
        startingDeadlineSeconds = 30;
        successfulJobsHistoryLimit = 1;
        failedJobsHistoryLimit = 3;
        jobTemplate.spec = {
          backoffLimit = 0;
          # Worst case is five 10s curls; the deadline is the backstop, and
          # `Forbid` means a slow run skips a tick rather than overlapping.
          activeDeadlineSeconds = 90;
          template = {
            metadata.labels = labels // {
              "app.kubernetes.io/name" = "exit-node-status-push";
            };
            spec = {
              restartPolicy = "Never";
              automountServiceAccountToken = false;
              containers = [
                {
                  name = "push";
                  # curl + sh and nothing else: the checks are answered by
                  # PromQL, so there is no JSON to parse here.
                  image = images.exitNodeStatusPush;
                  # The image's entrypoint is curl itself.
                  command = [ "/bin/sh" "/config/push.sh" ];
                  env = [
                    {
                      name = "PROM_URL";
                      value = "http://prometheus-operated.${ns}.svc.cluster.local:9090";
                    }
                    {
                      name = "GATUS_URL";
                      value = "http://gatus.${ns}.svc.cluster.local";
                    }
                    {
                      name = "EXIT_NODE_KEY";
                      value = exitNodePushKey;
                    }
                    {
                      name = "STALE_AFTER_SECONDS";
                      value = exitNodePushStaleAfter;
                    }
                    # Same Secret Gatus validates against, seeded by
                    # k3s-cluster-secrets. optional: true so an unseeded Secret
                    # fails this one job loudly instead of wedging the pod.
                    {
                      name = "GATUS_EXIT_NODE_TOKEN";
                      valueFrom.secretKeyRef = {
                        name = "gatus-exit-node-token";
                        key = "token";
                        optional = true;
                      };
                    }
                  ];
                  resources = {
                    requests = {
                      cpu = "10m";
                      memory = "32Mi";
                    };
                    limits.memory = "64Mi";
                  };
                  securityContext = {
                    runAsNonRoot = true;
                    runAsUser = 100;
                    readOnlyRootFilesystem = true;
                    allowPrivilegeEscalation = false;
                    capabilities.drop = [ "ALL" ];
                  };
                  volumeMounts = [
                    {
                      name = "script";
                      mountPath = "/config";
                      readOnly = true;
                    }
                  ];
                }
              ];
              volumes = [
                {
                  name = "script";
                  configMap.name = "exit-node-status-push";
                }
              ];
            };
          };
        };
      };
    }
  ];

  namespace = [
    {
      apiVersion = "v1";
      kind = "Namespace";
      metadata = {
        name = ns;
        labels = labels // {
          "pod-security.kubernetes.io/enforce" = "privileged";
        };
      };
    }
  ];
  # One Traefik Ingress per UI: Traefik already owns ports 80/443 on every node,
  # so host-based routing beats a LoadBalancer per UI -- three services cannot
  # each bind 80 on the same node, and this keeps the URLs port-free.
  #
  # TLS comes from the ACME-issued SAN certificate (see my.k3sMonitoring.tls),
  # and there is deliberately no HTTP-to-HTTPS redirect: the tailnet ACL does not
  # admit port 80 to these nodes, so no cleartext request ever arrives to be
  # redirected, and `.dev` is on the HSTS preload list -- a browser will not try
  # cleartext for these names in the first place. Probes use https:// URLs and get
  # certificate expiry checked along the way.
  mkIngress =
    {
      name,
      host,
      service,
      port,
    }:
    {
      apiVersion = "networking.k8s.io/v1";
      kind = "Ingress";
      metadata = {
        inherit name;
        namespace = ns;
        labels = labels // {
          "app.kubernetes.io/name" = name;
        };
      };
      spec = {
        ingressClassName = "traefik";
        tls = [
          {
            hosts = tls.hosts;
            secretName = tls.secretName;
          }
        ];
        rules = [
          {
            inherit host;
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = service;
                  port.number = port;
                };
              }
            ];
          }
        ];
      };
    };

  ingresses = [
    (mkIngress {
      name = "grafana";
      host = hosts.grafana;
      service = "kube-prometheus-stack-grafana";
      port = 80;
    })
    (mkIngress {
      name = "alertmanager";
      host = hosts.alertmanager;
      service = "kube-prometheus-stack-alertmanager";
      port = 9093;
    })
    (mkIngress {
      name = "gatus";
      host = hosts.status;
      service = "gatus";
      port = 80;
    })
  ];
in
{
  inherit
    namespace
    blackbox
    gatus
    exitNodeStatusPush
    ingresses
    ;

  # Probe endpoint of each status-page service, for the inventory's own probes.
  statusPageUrl = urls.status;
}
