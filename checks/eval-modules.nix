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
      # nixosModules added here as they are created in Tasks 2–5.
      ({ ... }: {
        # Stubs for forced options, grown in lockstep with the modules that
        # declare them (libreport.frp.* arrive with the frp-server module in
        # Task 5; setting them before the option exists is a hard NixOS error).
        sops.defaultSopsFile = pkgs.writeText "secrets" "{}";

        # Bare-system stubs so forcing `toplevel` clears NixOS' boot/fs
        # assertions. These are never deployed — they exist only so the
        # module smoke-test can evaluate (a host provides the real values).
        fileSystems."/".device = "tmpfs";
        fileSystems."/".fsType = "tmpfs";
        boot.loader.grub.devices = [ "nodev" ];
        system.stateVersion = "26.05";
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
  forced = eval.config.system.build.toplevel.drvPath;
} "echo ok > $out"
