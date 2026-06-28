{ config, lib, ... }:

{
  # node-exporter — exposes host metrics (CPU, RAM, disk, network) on :9100/metrics
  # for scraping by vmagent / VictoriaMetrics.
  #
  # All options are under `libreport.nodeExporter.*` with sensible defaults
  # so a host can opt in with a bare `inputs.libreport-os.nixosModules.node-exporter`
  # import and override only what it needs.
  options.libreport.nodeExporter = {
    enable = lib.mkEnableOption "node-exporter host metrics on :9100";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "Port for node-exporter to listen on.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = ''
        Address for node-exporter to bind to.
        Set to a Tailscale / WireGuard interface IP to restrict access
        to the monitoring network only.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the firewall for the node-exporter port.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--collector.filesystem.mount-points-exclude=^/(dev|proc|run|sys|mnt|media|var/lib/docker/.+)($|/)"
      ];
      description = "Extra command-line flags passed to node-exporter.";
    };
  };

  config = lib.mkIf config.libreport.nodeExporter.enable {
    services.prometheus.exporters.node = {
      enable = true;
      port = config.libreport.nodeExporter.port;
      listenAddress = config.libreport.nodeExporter.listenAddress;
      enabledCollectors = [
        "cpu"
        "diskstats"
        "filesystem"
        "loadavg"
        "meminfo"
        "netdev"
        "netstat"
        "time"
        "vmstat"
        "systemd"
        "processes"
        "tcpstat"
        "pressure"
      ];
      extraFlags = config.libreport.nodeExporter.extraFlags;
    };

    networking.firewall.allowedTCPPorts =
      lib.optionals config.libreport.nodeExporter.openFirewall
        [ config.libreport.nodeExporter.port ];
  };
}
