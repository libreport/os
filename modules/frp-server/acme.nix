{ config, lib, pkgs, ... }:

let
  # DNS-01 challenge script for 1Cloud.ru API.
  # Pure shell script — receives paths via environment variables.
  dnsChallengeScript = pkgs.writeShellScript "acme-dns-1cloud.sh"
    (builtins.readFile ./acme-dns-1cloud.sh);

  # Environment file for lego's exec DNS provider.
  # Provides EXEC_PATH (where lego finds the script) and paths the script needs.
  mkAcmeEnv = { sopsSecretPath }: pkgs.writeText "acme-exec-env" ''
    EXEC_PATH=${dnsChallengeScript}
    ACME_DNS_SECRETS=${sopsSecretPath}
    CURL_BIN=${lib.getExe pkgs.curl}
    JQ_BIN=${lib.getExe pkgs.jq}
  '';
in
{
  config = let
    frpDomain = config.libreport.frp.subDomainHost;
    certName = builtins.replaceStrings ["."] ["-"] frpDomain;
    certDir = "/var/lib/acme/${certName}";
  in {
    # ── ACME (Let's Encrypt) ─────────────────────────────────
    # Automatically provisions wildcard TLS certs via DNS-01 challenge.
    # The cert auto-renews and FRP is reloaded on renewal.
    security.acme = {
      acceptTerms = true;
      defaults.email = config.libreport.frp.acmeEmail;
      certs.${certName} = {
        domain = "*.${frpDomain}";
        extraDomainNames = [ frpDomain ];
        dnsProvider = "exec";
        environmentFile = mkAcmeEnv {
          sopsSecretPath = config.sops.secrets.frp_acme_environment.path;
        };
        reloadServices = [ "frp-libreport" ];
        # Uncomment the next line to use the Let's Encrypt staging CA for testing.
        # Staging certs will show browser warnings but don't count against rate limits.
        # extraLegoFlags = [ "--server" "https://acme-staging-v02.api.letsencrypt.org/directory" ];
      };
    };

    # ── FRP Control Channel TLS ──────────────────────────────
    # Point FRP server to the auto-provisioned certs for the frpc↔frps
    # control channel TLS (port 7000). FRP's public-facing HTTPS (:443) is
    # SNI passthrough, so the wildcard cert is NOT used to terminate
    # user-facing TLS here — only the control channel consumes it.
    services.frp.instances."libreport".settings = {
      transport.tls.certFile = "${certDir}/fullchain.pem";
      transport.tls.keyFile = "${certDir}/key.pem";
    };

    # ── Service ordering ─────────────────────────────────────
    # FRP must wait for ACME to provision certs before starting.
    # Without this, FRP fails on first deploy because cert files don't exist yet.
    # SupplementaryGroups gives the FRP service access to the "acme" group
    # so it can read the cert files (owned by root:acme by default).
    systemd.services.frp-libreport = {
      after = [ "acme-${certName}.service" ];
      wants = [ "acme-${certName}.service" ];
      serviceConfig.SupplementaryGroups = [ "acme" ];
    };

    # ── Secrets ──────────────────────────────────────────────
    # 1Cloud API credentials for DNS-01 challenges.
    # Expected contents:
    #   ONECLOUD_API_TOKEN=<token>
    #   ONECLOUD_DOMAIN_ID=37820
    #   ONECLOUD_DOMAIN=libreport.ru
    sops.secrets.frp_acme_environment = {
      # The ACME renewal service runs as User=acme Group=acme.
      # Without explicit ownership, the secret is owned by root:root (mode 0400)
      # and the ACME service can't read the 1Cloud API credentials.
      owner = "acme";
      group = "acme";
    };
  };
}
