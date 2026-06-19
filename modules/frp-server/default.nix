{ config, lib, pkgs, ... }:

let
  # Centralized port configuration — modify these to affect both
  # the firewall and the FRP server allow list in one place.
  allowedPorts = [ 22 80 443 7000 51820 ];
  allowedPortRanges = [
    { from = 30000; to = 32000; }
    { from = 33000; to = 34000; }
  ];

  # Convert the firewall-style ranges into the shape expected by services.frp
  frpAllowPortRanges =
    (map (p: { start = p; end = p; }) allowedPorts)
    ++ (map (r: { start = r.from; end = r.to; }) allowedPortRanges);
in
{
  options.libreport.frp = {
    subDomainHost = lib.mkOption {
      type = lib.types.str;
      description = ''
        Base domain for FRP subdomain routing (e.g. mow1.libreport.ru).
        Required on purpose — it has no default so a host that forgets to set
        it fails to build rather than silently routing tunnels to the wrong
        domain. (Previously leaked as a mkDefault of the operator's domain.)
      '';
    };
    acmeEmail = lib.mkOption {
      type = lib.types.str;
      description = "Email for ACME (Let's Encrypt) registration. Required.";
    };
  };

  # NOTE: nginx.nix lives in this directory but is intentionally NOT imported
  # here. The current architecture is FRP-direct on :80/:443 (no nginx front);
  # importing nginx.nix would make nginx and frps both bind :80 and :443. It is
  # retained for a possible future TLS-terminating front end.
  imports = [ ./acme.nix ];

  config = {
    environment.systemPackages = map lib.lowPrio [
      pkgs.frp
    ];

    # Allow some ports (controlled above)
    networking.firewall.enable = true;
    networking.firewall.allowedTCPPorts = allowedPorts;
    networking.firewall.allowedUDPPorts = allowedPorts;
    networking.firewall.allowedTCPPortRanges = allowedPortRanges;
    networking.firewall.allowedUDPPortRanges = allowedPortRanges;

    services.frp.instances."libreport" = {
      enable = true;
      role = "server";
      settings = {
        # Network bind settings
        bindAddr = "0.0.0.0";
        bindPort = 7000;
        quicBindPort = 7000;

        # Virtual host ports — FRP serves HTTP on :80 and HTTPS on :443 directly,
        # routing inbound tunnels by Host header (HTTP) and SNI (HTTPS).
        # NOTE: FRP's vhostHTTPS is SNI passthrough — it does NOT terminate TLS
        # with a shared cert. Each https-type frpc proxy must bring its own cert
        # (or use http + its own TLS).
        vhostHTTPPort = 80;
        vhostHTTPSPort = 443;

        # Port ranges to allow frpc to bind (derived from the centralized config)
        allowPorts = frpAllowPortRanges;

        # Base domain for subdomain routing — sourced from the forced option
        # libreport.frp.subDomainHost (was a mkDefault leak of the operator domain).
        subDomainHost = config.libreport.frp.subDomainHost;

        auth.method = "token";
        auth.token = "{{ .Envs.FRP_AUTH_TOKEN }}";

        # Server Dashboard
        webServer.addr = "127.0.0.1";
        webServer.port = 7500;
        webServer.user = "{{ .Envs.FRP_WEBSERVER_USER }}";
        webServer.password = "{{ .Envs.FRP_WEBSERVER_PASSWORD }}";
      };
    };

    sops.secrets.frp_server_environment = {
      # Restart frps whenever this secret's *value* changes. systemd reads
      # EnvironmentFile= exactly once at service start — it does not watch the
      # file — so without this, sops-nix silently rewrites
      # /run/secrets/frp_server_environment during activation while frps keeps
      # running with the stale FRP_AUTH_TOKEN in memory.
      restartUnits = [ "frp-libreport.service" ];
    };

    systemd.services.frp-libreport = {
      serviceConfig.EnvironmentFile = config.sops.secrets.frp_server_environment.path;
    };
  };
}
