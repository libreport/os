# libreport/os

Generic NixOS modules for FRP hosting cells. This is the **OS/service layer**;
it ships no hosts, IPs, or secrets of its own. Consume it from your private
host repo.

## Consume

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.libreport-os.url = "github:libreport/os";
  inputs.libreport-os.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, libreport-os, ... }@inputs: {
    nixosConfigurations.my-host = libreport-os.lib.mkNixosConfig {
      path = ./hosts/my-host;
      inherit (self) inputs;
    };
  };
}
```

A host `default.nix` imports the modules it wants via `inputs.libreport-os.nixosModules.*`
and sets the required options (below). `mkNixosConfig` auto-includes disko and
sops-nix and passes `inputs` through as `specialArgs` (so host files can read
`inputs.libreport-os.nixosModules.*`).

## Required options (no default — build fails if omitted)

| Option | Example |
|---|---|
| `libreport.frp.subDomainHost` | `"mow1.libreport.ru"` |
| `libreport.frp.acmeEmail` | `"you@example.com"` |

## Optional options

| Option | Default |
|---|---|
| `libreport.users.root.hashedPasswordFile` | `null` (key-only root) |
| `libreport.users.root.sshKeys` | `[]` |
| `libreport.users.libreport.hashedPasswordFile` | `null` |
| `libreport.users.libreport.sshKeys` | `[]` |
| `libreport.users.libreport.extraGroups` | `[ "wheel" ]` |

## Required secret keys (your sops `secrets.yaml` must contain)

- `frp_server_environment` → `FRP_AUTH_TOKEN`, `FRP_WEBSERVER_USER`, `FRP_WEBSERVER_PASSWORD`
- `frp_acme_environment` → `ONECLOUD_API_TOKEN`, `ONECLOUD_DOMAIN_ID`, `ONECLOUD_DOMAIN`

The consumer must also set `sops.defaultSopsFile`.

## ⚠️ MongoDB credentials are placeholders

`modules/mongodb` ships with `MONGO_INITDB_ROOT_PASSWORD = "supersecret"` and
Mongo Express basic auth disabled. Override these before relying on this module
in production.

## Modules

`base`, `zsh`, `ssh`, `podman`, `nix`, `sops`, `users`, `frp-server`, `mongodb`.
