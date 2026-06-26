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
        Base domain for FRP subdomain routing (e.g. cell.example.com).
        Required on purpose — it has no default so a host that forgets to set
        it fails to build rather than silently routing tunnels to the wrong
        domain. (Previously leaked as a mkDefault of the operator's domain.)
      '';
    };
    acme = {
      email = lib.mkOption {
        type = lib.types.str;
        description = "Email for ACME (Let's Encrypt) registration. Required.";
      };

      provider = lib.mkOption {
        type = lib.types.str;
        description = ''
          lego DNS provider name, e.g. "cloudflare", "route53", "exec".
          For "exec", set `execScript` — the module wires EXEC_PATH for you.
        '';
      };

      execScript = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Executable store path called by lego's exec provider.
          Required iff provider == "exec"; ignored otherwise. Must be an
          executable (e.g. `lib.getExe (pkgs.writeShellApplication {...})`),
          not a package root. Must wrap its own runtime deps (curl, jq, …).
        '';
      };
    };
  };

  # nginx (nginx.nix) terminates public TLS on :443 with the *.<subDomainHost>
  # Let's Encrypt wildcard from acme.nix, then proxies HTTP to FRP's internal
  # vhostHTTPPort. FRP therefore must NOT bind :80/:443. TCP/UDP proxies use
  # their own ports and are unaffected.
  imports = [ ./acme.nix ./nginx.nix ];

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

        # Virtual host ports — INTERNAL only. nginx (nginx.nix) owns public
        # :80/:443, terminates TLS with the LE wildcard, then proxies HTTP here.
        # FRP routes http-type tunnels by Host header on vhostHTTPPort (8080).
        # vhostHTTPSPort (8443) is internal and unused publicly: FRP's vhostHTTPS
        # is SNI passthrough with no shared cert, so public TLS is nginx's job.
        # TCP/UDP proxies bind their own ports (7000/51820/ranges), unaffected.
        vhostHTTPPort = 8080;
        vhostHTTPSPort = 8443;

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
