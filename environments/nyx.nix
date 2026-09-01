
{ config, pkgs, ... }:

let
  link = config.lib.file.mkOutOfStoreSymlink;   # Symlink auf Live-Pfad, nicht in den Store
  sync = "${config.home.homeDirectory}/.sync";
in
{

  home.packages = with pkgs; [
    uv
    portfolio
    digikam
  ];

  # Syncthing-Ordner als suffixlose Symlinks in ~ (Richtung steckt im Ordner-Präfix)
  home.file = {
    "dokumente".source   = link "${sync}/share-dokumente";
    "notizen".source     = link "${sync}/share-notizen";
    "Documents".source   = link "${sync}/backup-nyx/Documents";
    "Downloads".source   = link "${sync}/backup-nyx/Downloads";
    "Screenshots".source = link "${sync}/backup-nyx/Screenshots";
  };

  # Override specific dotfiles
  # xdg.configFile."myapp/config".source = ./dotfiles/env1-config;
}
