{ pkgs, lib, config, ... }:
let
  cfg = config.libreport.users;
in
{
  options.libreport.users = {
    root = {
      hashedPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to root's hashed password file (e.g. a sops secret). null = key-only login.";
      };
      sshKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "SSH public keys for root.";
      };
    };
    libreport = {
      hashedPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to the libreport user's hashed password file (e.g. a sops secret).";
      };
      sshKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "SSH public keys for the libreport user.";
      };
      extraGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "wheel" ];
        description = "Extra groups for the libreport user.";
      };
    };
  };

  config = {
    users.defaultUserShell = pkgs.zsh;
    users.users.root = {
      hashedPasswordFile = lib.mkIf (cfg.root.hashedPasswordFile != null) cfg.root.hashedPasswordFile;
      openssh.authorizedKeys.keys = cfg.root.sshKeys;
    };
    users.users.libreport = {
      isNormalUser = true;
      extraGroups = cfg.libreport.extraGroups;
      hashedPasswordFile = lib.mkIf (cfg.libreport.hashedPasswordFile != null) cfg.libreport.hashedPasswordFile;
      openssh.authorizedKeys.keys = cfg.libreport.sshKeys;
    };
  };
}
