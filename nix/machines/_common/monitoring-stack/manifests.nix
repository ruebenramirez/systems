# Plain Kubernetes manifests for the monitoring stack, generated from the fleet
# inventory and auto-deployed by k3s. kube-prometheus-stack itself arrives as a
# Helm chart (see ../services/k3s-monitoring.nix); what is here is the part that
# is cheaper to write than to chart: the blackbox exporter whose probes the
# inventory defines, the status page whose endpoints the inventory defines, and
# the namespace both live in.
{
  inventory,
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
    ingresses
    ;

  # Probe endpoint of each status-page service, for the inventory's own probes.
  statusPageUrl = urls.status;
}
