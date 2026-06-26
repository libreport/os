# Force-evaluates the frp-server module with the EXEC DNS provider, proving the
# exec branch of acme.nix constructs: mkExecEnv interpolates a real EXEC_PATH,
# and the exec/execScript assertions do NOT false-positive on a valid exec
# config. The companion eval-modules check covers the native branch. See
# checks/eval-modules.nix for the rationale on unsafeDiscardStringContext and the
# bare-system stubs (we force toplevel's drvPath so the acme cert config —
# including the exec environmentFile — is evaluated, without building it).
inputs:
let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  eval = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      inputs.sops-nix.nixosModules.sops
      inputs.self.nixosModules.frp-server
      ({ lib, ... }: {
        libreport.frp.subDomainHost   = "test.example.com";
        libreport.frp.acme.email      = "test@example.com";
        libreport.frp.acme.provider   = "exec";
        libreport.frp.acme.execScript = lib.getExe (pkgs.writeShellScriptBin "acme-noop" "exit 0");
        sops.defaultSopsFile     = pkgs.writeText "secrets" "{}";
        sops.validateSopsFiles   = false;
        sops.age.keyFile         = "/dev/null";
        fileSystems."/".device   = "tmpfs";
        fileSystems."/".fsType   = "tmpfs";
        boot.loader.grub.devices = [ "nodev" ];
        system.stateVersion      = "26.05";
      })
    ];
  };
in
pkgs.runCommand "eval-modules-exec-check" {
  forced = builtins.unsafeDiscardStringContext eval.config.system.build.toplevel.drvPath;
} "echo ok > $out"
