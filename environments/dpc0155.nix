{ config, lib, pkgs, ... }:

{
  # TODO: make explicit whitelist work
  # whitelist unfree software
  nixpkgs.config.allowUnfree = true;

  # Environment specific packages
  home.packages = with pkgs; [
    teams-for-linux
    vscode

    ### CLOUD ### 
    azure-cli
    fluxcd
    kubectl
    kubernetes-helm
    kubelogin
    kubectx
    kubecolor
    kubeseal
    krew

    ### DEVELOPMENT PACKAGES ###
    nodejs_22
    ungoogled-chromium
    maven
    pnpm
    yq
    jq

    ### MISC ###
    gimp
    xfce.thunar
    pandoc
  ];

  home.file."bin/chrome-disabled-web-security" = {
    text = ''
      #!/bin/sh
      exec chromium --disable-web-security --user-data-dir="/tmp/chromium-disabled-ws"
    '';
    executable = true;
  };

  # Copy theme files into k9s skins directory.
  home.file.".config/k9s/skins" = {
    source = builtins.toPath ../themes/k9s/skins; 
    recursive = true;
  };

  # Optionally, manage your k9s config to set the desired skin.
  home.file.".config/k9s/config.yaml" = {
    source = ../dotfiles/k9s_config.yaml;
  };

}

