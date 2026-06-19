{ pkgs, lib, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    interactiveShellInit = ''
      source ${pkgs.grml-zsh-config}/etc/zsh/zshrc
    '';
    promptInit = ""; # otherwise it'll override the grml prompt
    syntaxHighlighting = {
      enable = true;
      # See https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/docs/highlighters/main.md
      styles = {
        # To differentiate aliases from other command types
        alias = "fg=magenta,bold";
        # To have paths colored instead of underlined
        path = "fg=cyan,bold";
        # To disable highlighting of globbing expressions
        # globbing='none'
      };
    };
    ohMyZsh = {
      enable = true;
      plugins = [
        "dotenv"
        "podman"
        "git"
        "vi-mode"
      ];
    };
  };
}
