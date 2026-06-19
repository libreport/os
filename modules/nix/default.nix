{ lib, ... }:

{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ ];

  boot.nixStoreMountOpts = [ "ro" ];
  nix = {
    settings = {
      auto-optimise-store = true;
      trusted-users = [ "@wheel" ];
      allowed-users = [ "@wheel" ];
      experimental-features = [ "nix-command" "flakes" ];
      # fixing the download buffer is full warning;
      download-buffer-size = 524288000; # 500 MiB in bytes
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d --max-freed $((64 * 1024**3))";
    };
    optimise = {
      automatic = true;
    };
    # extraOptions = ''
    #   builders-use-substitutes = true
    # '';
  };
}
