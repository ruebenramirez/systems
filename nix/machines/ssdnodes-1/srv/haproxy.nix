{
  # HAProxy is the public TCP/443 SNI front for ssdnodes-1:
  #   - SNI www.microsoft.com -> sing-box Reality (127.0.0.1:8443), raw passthrough
  #   - everything else        -> nginx HTTPS (127.0.0.1:8444) with PROXY protocol
  #
  # NOTE: the NixOS services.haproxy module already emits a `global` section
  # (stats socket), so this config must NOT define another one.
  services.haproxy = {
    enable = true;
    config = ''
      defaults
        mode    tcp
        option  tcplog
        timeout connect 5s
        timeout client  12h
        timeout server  12h

      frontend tls_in
        bind :443
        bind [::]:443 v6only
        tcp-request inspect-delay 5s
        tcp-request content accept if { req_ssl_hello_type 1 }
        use_backend reality if { req_ssl_sni -i www.microsoft.com }
        default_backend nginx_https

      backend reality
        server singbox 127.0.0.1:8443

      backend nginx_https
        server nginx 127.0.0.1:8444 send-proxy-v2
    '';
  };

  # Start the front door after its backends.
  systemd.services.haproxy = {
    wants = [ "nginx.service" "sing-box.service" ];
    after = [ "nginx.service" "sing-box.service" ];
  };
}
