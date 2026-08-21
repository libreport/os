{ config, lib, pkgs, ... }:

let
  cfg = config.libreport.stun;
in
{
  # stun — local STUN responder for self-hosted DERP regions.
  #
  # Runs tailscale's derper in STUN-only mode (`-derp=false -stun`) so tailnet
  # clients can measure the true latency of a DERP region and learn their real
  # public address. derper comes from the tailscale package's separate
  # "derper" output — no tailscaled, no services.tailscale, nothing enrolls.
  #
  # Why answer STUN on the relay host instead of tunnelling it through frp:
  # frp does not preserve client source addresses, so a STUN request that
  # rides the tunnel reaches the backend carrying the tunnel client's
  # address — the reply then tells the client its public address is a
  # private cluster IP, and the measured region latency includes the whole
  # tunnel round-trip. Answering on the relay returns the client's real
  # address and a one-hop RTT.
  #
  # NOTE: the STUN UDP port must actually be free on the host. If a frp UDP
  # proxy holds the same remotePort, remove it before enabling this module,
  # or the unit crash-loops on EADDRINUSE.
  options.libreport.stun = {
    enable = lib.mkEnableOption "local STUN responder (derper, STUN-only mode)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3478;
      description = ''
        UDP port to serve STUN on. Must equal the port advertised by the
        DERP map (headscales's derp.server.stun_listen_addr).
      '';
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      example = "relay.example.com";
      description = ''
        Address derper binds both the STUN UDP socket and its status TCP
        listener to (derper's -a flag pins the two together). Accepts an
        IPv4 literal or a hostname — Go resolves hostnames at listen time,
        so the resolved address is re-picked on every service start. Using
        the same hostname the DERP map advertises makes the bind track IP
        changes: update the DNS record, restart the unit (or reboot), done.

        Resolution happens ONCE at process start; a running derper does not
        follow DNS. The name must resolve to an address configured on this
        host (EADDRNOTAVAIL otherwise — loud, by design).

        Deliberately has no default: never wildcard-bind STUN on a relay.
        A wildcard-bound UDP socket does not remember which local address a
        request arrived on, so the kernel re-picks the reply's source by
        route to the destination — and clients using connected sockets
        (every STUN client, tailscaled included) silently drop a reply whose
        source differs from the address they probed.
      '';
    };

    statusPort = lib.mkOption {
      type = lib.types.port;
      default = 7480;
      description = ''
        TCP port for derper's status listener. With -derp=false derper still
        runs exactly one HTTP listener on the -a address serving a "derp
        disabled" status page (cmd/derper starts it unconditionally;
        -http-port=-1 only disables the port-80 side listener). The firewall
        does not open this port — pick anything free and leave it dark.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the firewall for the STUN UDP port. Defaults to true: unlike a
        metrics endpoint, a STUN responder is useless unless reachable, and
        it is not an amplification vector (a ~32-byte reply to a 40-byte
        request). Set to false if the port is already opened elsewhere
        (e.g. the frp-server module's allowedPorts).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.stun-responder = {
      description = "STUN responder (derper, STUN-only) for the DERP region";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # With a hostname in bindAddress the first start can race DNS
      # readiness at boot; let systemd keep retrying well past its default
      # start limit (5 starts / 10s) while the resolver warms up.
      startLimitIntervalSec = 120;
      startLimitBurst = 24;

      serviceConfig = {
        # NOTE: tailscale is a multi-output package and bin/derper lives in
        # the separate `derper` output (postInstall moves it out of `out`),
        # so the output attribute must be selected explicitly —
        # lib.getExe / getExe' would yield the default output, which has no
        # such file.
        ExecStart =
          "${pkgs.tailscale.derper}/bin/derper -c /var/lib/derper/derper.key -derp=false -stun -stun-port=${toString cfg.port} -http-port=-1 -a=${cfg.bindAddress}:${toString cfg.statusPort}";
        # derper requires a -c state path and auto-generates its node key
        # there on first start. The key is unused in STUN-only mode (derper
        # constructs its DERP server object unconditionally) but harmless.
        StateDirectory = "derper";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_NETLINK" ];
        CapabilityBoundingSet = "";
        RestrictNamespaces = true;
        LockPersonality = true;
      };
    };

    networking.firewall.allowedUDPPorts =
      lib.optionals cfg.openFirewall [ cfg.port ];
  };
}
