{ config, lib, pkgs, ... }:

# Nginx reverse proxy that terminates TLS for FRP's HTTP vhost routing
# and exposes the FRP dashboard on a dedicated subdomain.
#
# Architecture:
#   Client → https://sub.cell.example.com:443 → nginx (TLS termination)
#                                                  → http://127.0.0.1:8080 → FRP (vhost routing by Host header)
#                                                                                   → frpc → local service
#
#   Admin  → https://dashboard.cell.example.com:443 → nginx (TLS termination)
#                                                       → http://127.0.0.1:7500 → FRP dashboard
#
# Port 80 redirects all HTTP traffic to HTTPS.

let
  frpDomain = config.libreport.frp.subDomainHost;
  certName = builtins.replaceStrings ["."] ["-"] frpDomain;
  certDir = "/var/lib/acme/${certName}";
  frpHTTPPort = config.services.frp.instances."libreport".settings.vhostHTTPPort or 8080;
in
{
  config = lib.mkIf config.services.frp.instances."libreport".enable {
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;

      # Rate limit zones.
      # frp:       10r/s per IP for user tunnels (~160k unique IPs in 10m).
      # dashboard: 2r/s per IP for admin dashboard (stricter, brute-force defense).
      commonHttpConfig = ''
        limit_req_zone $binary_remote_addr zone=frp:10m rate=10r/s;
        limit_req_zone $binary_remote_addr zone=dashboard:10m rate=2r/s;
      '';

      virtualHosts.${frpDomain} = {
        serverAliases = [ "*.${frpDomain}" ];

        # HTTPS with ACME wildcard cert + HTTP→HTTPS redirect
        forceSSL = true;
        sslCertificate = "${certDir}/fullchain.pem";
        sslCertificateKey = "${certDir}/key.pem";

        # Proxy all requests to FRP's internal HTTP vhost port.
        # FRP routes by the Host header (subdomain matching).
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString frpHTTPPort}";
          proxyWebsockets = true;
          extraConfig = ''
            # Rate limiting (pentest remediation #25)
            limit_req zone=frp burst=20 nodelay;
            limit_req_status 429;

            # Security headers (pentest remediation #25)
            add_header Strict-Transport-Security "max-age=15768000; includeSubDomains" always;
            add_header X-Frame-Options "SAMEORIGIN" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header Referrer-Policy "strict-origin-when-cross-origin" always;
          '';
        };
      };

      # Dashboard — exact server_name match takes priority over the wildcard above.
      virtualHosts."dashboard.${frpDomain}" = {
        forceSSL = true;
        sslCertificate = "${certDir}/fullchain.pem";
        sslCertificateKey = "${certDir}/key.pem";

        locations."/" = {
          proxyPass = "http://127.0.0.1:7500";
          proxyWebsockets = true;
          extraConfig = ''
            # Stricter rate limiting for admin dashboard
            limit_req zone=dashboard burst=5 nodelay;
            limit_req_status 429;

            # Security headers
            add_header Strict-Transport-Security "max-age=15768000; includeSubDomains" always;
            add_header X-Frame-Options "SAMEORIGIN" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header Referrer-Policy "strict-origin-when-cross-origin" always;
          '';
        };
      };
    };

    # nginx needs to read the ACME certificate files (owned by root:acme, mode 0440).
    users.users.nginx.extraGroups = [ "acme" ];

    # nginx must wait for ACME to provision certificates before starting.
    # Without this, nginx fails on first deploy because cert files don't exist yet.
    systemd.services.nginx = {
      after = [ "acme-${certName}.service" ];
      wants = [ "acme-${certName}.service" ];
    };
  };
}
