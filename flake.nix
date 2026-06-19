{
  description = "libreport/os — generic NixOS modules for FRP hosting cells";

  inputs.nixpkgs.url  = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.disko.url    = "github:nix-community/disko";
  inputs.disko.inputs.nixpkgs.follows = "nixpkgs";
  inputs.sops-nix.url = "github:mic92/sops-nix";
  inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, disko, sops-nix, ... }@inputs: {
    nixosModules = {
      # Grown in Tasks 2–5: base, zsh, ssh, podman, nix, mongodb, sops, users, frp-server
      base    = ./modules/base;
      zsh     = ./modules/base/zsh.nix;
      ssh     = ./modules/base/ssh.nix;
      podman  = ./modules/base/podman.nix;
      nix     = ./modules/nix;
      mongodb = ./modules/mongodb;
    };

    # Consumer host builder. `inputs` is the CONSUMER's inputs attrset (so host
    # files can write `inputs.libreport-os.nixosModules.*` and `inputs.nixpkgs`);
    # disko + sops-nix come from THIS flake's own inputs and are auto-included.
    #
    # Note: the param is named `inputs`, which shadows the outer `@inputs` alias
    # inside this lambda — but NOT the individually-destructured params `disko`
    # and `sops-nix`. Those remain in lexical scope, so we reference them
    # directly (not `inputs.disko`) to pull from this flake's own inputs without
    # requiring the consumer to declare disko/sops-nix itself.
    lib.mkNixosConfig = { path, inputs, modules ? [ ] }:
      inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
        ] ++ modules ++ [ path ];
      };

    checks.x86_64-linux.eval-modules = import ./checks/eval-modules.nix inputs;
  };
}
