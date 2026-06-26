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
| `libreport.frp.acme.email` | `"you@example.com"` |
| `libreport.frp.acme.provider` | `"cloudflare"` / `"route53"` / `"exec"` |

## Optional options

| Option | Default |
|---|---|
| `libreport.users.root.hashedPasswordFile` | `null` (key-only root) |
| `libreport.users.root.sshKeys` | `[]` |
| `libreport.users.libreport.hashedPasswordFile` | `null` |
| `libreport.users.libreport.sshKeys` | `[]` |
| `libreport.users.libreport.extraGroups` | `[ "wheel" ]` |
| `libreport.frp.acme.execScript` | `null` (required iff `provider == "exec"`) |

## Required secret keys (your sops `secrets.yaml` must contain)

- `frp_server_environment` → `FRP_AUTH_TOKEN`, `FRP_WEBSERVER_USER`, `FRP_WEBSERVER_PASSWORD`
- `frp_acme_environment` → contents depend on your provider. **Native** providers hold lego's expected vars (e.g. `CLOUDFLARE_API_TOKEN`). The **exec** provider sources `$ACME_DNS_SECRETS`; the file holds whatever keys your exec script defines.

The consumer must also set `sops.defaultSopsFile`.

## ⚠️ MongoDB credentials are placeholders

`modules/mongodb` ships with `MONGO_INITDB_ROOT_PASSWORD = "supersecret"` and
Mongo Express basic auth disabled. Override these before relying on this module
in production.

## Pluggable DNS-01

`libreport.frp.acme.provider` selects any lego DNS provider.

- **Native** (e.g. `cloudflare`, `route53`): set `provider` + `email`; put the provider's expected env vars in your `frp_acme_environment` secret. No script needed.
- **exec** (custom-script challenge, e.g. a vendor API lego doesn't support): also set `execScript` to an *executable* store path (typically `lib.getExe (pkgs.writeShellApplication { runtimeInputs = [...]; text = ...; })`). Your script sources `$ACME_DNS_SECRETS` for credentials and must bring its own runtime deps.

## Modules

`base`, `zsh`, `ssh`, `podman`, `nix`, `sops`, `users`, `frp-server`, `mongodb`.
