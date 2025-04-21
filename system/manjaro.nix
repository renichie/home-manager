
{ config, lib, pkgs, ... }:

{

  home.packages = with pkgs; [
    nordic # gnome theme
  ];

  home.sessionVariables = {
    PATH = "${pkgs.nix}/bin:/nix/var/nix/profiles/default/bin:/nix/store:$PATH";
  };

  # GTK configuration
  gtk = {
    enable = true;
    theme = {
      name = "Nordic"; # Use the dark variant of the Nordic theme
      package = pkgs.nordic;
    };
  };


  # Add the activation script for GNOME settings
  home.activation = {
    set-gnome-dark-mode = lib.hm.dag.entryAfter ["writeBoundary"] ''
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
    '';
  };

}
