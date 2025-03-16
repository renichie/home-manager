{ config, lib, pkgs, ... }:

{
  # TODO: make explicit whitelist work
  # whitelist unfree software
  nixpkgs.config.allowUnfree = true;
  #  nixpkgs.config.allowUnfreePredicate =
  #    pkg: builtins.elem (pkgs.lib.getName pkg) [
  #      "teams-for-linux" "idea-ultimate" "vscode"
  #    ];

  # Environment specific packages
  home.packages = with pkgs; [
    teams-for-linux
    jetbrains.idea-ultimate
    vscode
    fluxcd

    ### CLOUD ### 
    azure-cli
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

    ### MISC ###
    gimp
    xfce.thunar
    pandoc

    yq
    jq
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

