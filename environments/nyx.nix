
{ config, pkgs, ... }:

{

  home.packages = with pkgs; [
    uv
    portfolio
  ];
  # Override specific dotfiles
  # xdg.configFile."myapp/config".source = ./dotfiles/env1-config;
}
