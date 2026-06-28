# Force-evaluates every nixosModule with stubbed values for forced options.
# A malformed module or a missing forced option throws HERE (in CI / nix flake
# check) instead of at consumer build time.
#
# Passed the flake inputs attrset positionally (nixpkgs, disko, sops-nix, self).
inputs:
let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  eval = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      inputs.self.nixosModules.base
      inputs.self.nixosModules.zsh
      inputs.self.nixosModules.ssh
      inputs.self.nixosModules.podman
      inputs.self.nixosModules.nix
      inputs.self.nixosModules.mongodb
      inputs.self.nixosModules.sops
      inputs.self.nixosModules.users
      inputs.self.nixosModules.frp-server
      inputs.self.nixosModules.node-exporter
      # nixosModules added here as they are created in Tasks 2–5.
      ({ config, ... }: let frpCertName = builtins.replaceStrings ["."] ["-"] config.libreport.frp.subDomainHost; in {
        # Stubs for forced options, grown in lockstep with the modules that
        # declare them. libreport.frp.* are declared by the frp-server module,
        # so they're valid now (they were absent through Tasks 1–4).
        libreport.frp.subDomainHost = "test.example.com";
        libreport.frp.acme.email    = "test@example.com";
        libreport.frp.acme.provider = "cloudflare";   # native branch — no execScript
        sops.defaultSopsFile = pkgs.writeText "secrets" "{}";
        # The stub secrets file is a placeholder, not a real sops file, and under
        # `nix eval` a writeText path isn't realized into the store — so disable
        # sops-nix's "file must be in the store" assertion. Real consumer hosts
        # use their genuine secrets.yaml and keep the default (validation on).
        sops.validateSopsFiles = false;

        # Bare-system stubs so forcing `toplevel` clears NixOS' boot/fs
        # assertions. These are never deployed — they exist only so the
        # module smoke-test can evaluate (a host provides the real values).
        fileSystems."/".device = "tmpfs";
        fileSystems."/".fsType = "tmpfs";
        boot.loader.grub.devices = [ "nodev" ];
        system.stateVersion = "26.05";

        # Design invariants for the frp-server public TLS front-end. Locks in:
        # nginx terminates public :443; FRP vacates :80/:443; nginx reloads when
        # the LE cert renews. Guards against disabling nginx.nix, which would
        # leave public TLS un-terminated (FRP's vhostHTTPS is SNI passthrough,
        # not shared-cert termination).
        assertions = [
          { assertion = config.services.nginx.enable;
            message = "frp-server: nginx.nix front-end must be enabled to terminate public TLS"; }
          { assertion = config.services.nginx.virtualHosts.${config.libreport.frp.subDomainHost}.forceSSL or false;
            message = "frp-server: nginx vhost must forceSSL (HTTP→HTTPS redirect) for the public front-end"; }
          { assertion = (config.services.frp.instances."libreport".settings.vhostHTTPPort or null) == 8080;
            message = "frp-server: vhostHTTPPort must be 8080 (internal) so nginx owns :80"; }
          { assertion = (config.services.frp.instances."libreport".settings.vhostHTTPSPort or null) == 8443;
            message = "frp-server: vhostHTTPSPort must be 8443 (internal) so nginx owns :443"; }
          { assertion = builtins.elem "nginx" (config.security.acme.certs.${frpCertName}.reloadServices or [ ]);
            message = "frp-server: 'nginx' must be in the LE cert reloadServices (else stale cert after renewal)"; }
        ];
      })
    ];
  };
in
pkgs.runCommand "eval-modules-check" {
  # Force evaluation of the NixOS toplevel's derivation path. Constructing
  # `toplevel` pulls in activation scripts, services, users, sops secrets and
  # acme certs — effectively the whole config — so a malformed module or a
  # missing referenced forced option throws HERE instead of at consumer build
  # time. We intentionally do NOT `deepSeq eval.config`: NixOS configs contain
  # self-referential cycles that make deepSeq stack-overflow.
  #
  # unsafeDiscardStringContext is essential: a store-path string carries its
  # derivation's outputs as build dependencies, so WITHOUT it `nix flake check`
  # (which builds checks) would build the entire bare-NixOS toplevel. We only
  # need the eval side-effect (forcing toplevel construction), not the build.
  forced = builtins.unsafeDiscardStringContext eval.config.system.build.toplevel.drvPath;
} "echo ok > $out"
