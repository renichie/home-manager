
{ config, pkgs, ... }:

{

  home.packages = with pkgs; [
    uv
    portfolio
    digikam
  ];
  # Override specific dotfiles
  # xdg.configFile."myapp/config".source = ./dotfiles/env1-config;
}
