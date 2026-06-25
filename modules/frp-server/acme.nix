{ config, lib, pkgs, ... }:

let
  acme = config.libreport.frp.acme;

  # lego's "exec" DNS provider runs EXEC_PATH as a subprocess. We pass the
  # consumer's credentials file via ACME_DNS_SECRETS, which the exec script
  # sources (see README, "Pluggable DNS-01"). The script is responsible for its
  # own runtime deps — we inject no tool paths.
  mkExecEnv = { execScript, credsPath }: pkgs.writeText "acme-exec-env" ''
    EXEC_PATH=${execScript}
    ACME_DNS_SECRETS=${credsPath}
  '';

  # Native providers: lego sources the credentials file directly (it must hold
  # that provider's expected vars). exec: we wrap script + creds path into a
  # store env file lego sources.
  environmentFile =
    if acme.provider == "exec"
    then mkExecEnv {
      inherit (acme) execScript;
      credsPath = config.sops.secrets.frp_acme_environment.path;
    }
    else config.sops.secrets.frp_acme_environment.path;
in
{
  config = let
    frpDomain = config.libreport.frp.subDomainHost;
    certName = builtins.replaceStrings ["."] ["-"] frpDomain;
    certDir = "/var/lib/acme/${certName}";
  in {
    assertions = [
      { assertion = !(acme.provider == "exec") || acme.execScript != null;
        message = ''libreport.frp.acme.execScript is required when provider == "exec".''; }
      { assertion = (acme.provider == "exec") || acme.execScript == null;
        message = ''libreport.frp.acme.execScript is only meaningful when provider == "exec".''; }
    ];

    # ── ACME (Let's Encrypt) ─────────────────────────────────
    # Provisions wildcard TLS certs via DNS-01 using any lego DNS provider
    # (libreport.frp.acme.provider). Auto-renews; FRP is reloaded on renewal.
    security.acme = {
      acceptTerms = true;
      defaults.email = acme.email;
      certs.${certName} = {
        domain = "*.${frpDomain}";
        extraDomainNames = [ frpDomain ];
        dnsProvider = acme.provider;
        inherit environmentFile;
        reloadServices = [ "frp-libreport" "nginx" ];
        # Uncomment for the Let's Encrypt staging CA (browser warnings, no rate limit):
        # extraLegoFlags = [ "--server" "https://acme-staging-v02.api.letsencrypt.org/directory" ];
      };
    };

    # ── FRP Control Channel TLS ──────────────────────────────
    services.frp.instances."libreport".settings = {
      transport.tls.certFile = "${certDir}/fullchain.pem";
      transport.tls.keyFile = "${certDir}/key.pem";
    };

    # ── Service ordering ─────────────────────────────────────
    systemd.services.frp-libreport = {
      after = [ "acme-${certName}.service" ];
      wants = [ "acme-${certName}.service" ];
      serviceConfig.SupplementaryGroups = [ "acme" ];
    };

    # ── Secrets ──────────────────────────────────────────────
    # DNS-01 credentials. Contents are provider-specific (consumer's secrets.yaml):
    #   native: lego's expected vars (e.g. CLOUDFLARE_API_TOKEN)
    #   exec:    whatever the consumer's script sources (passed via $ACME_DNS_SECRETS)
    sops.secrets.frp_acme_environment = {
      owner = "acme";
      group = "acme";
    };
  };
}
