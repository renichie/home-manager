{ config, lib, pkgs, ... }:
let
  homeDir = config.home.homeDirectory;
in
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
    krew # needs `export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH` for installs

    ### DEVELOPMENT PACKAGES ###
    nodejs_22
    ungoogled-chromium
    maven
    pnpm
    yq
    jq
    bun # needs `export PATH="$HOME/.bun/bin:$PATH"` for global installs

    ### MISC ###
    gimp
    xfce.thunar
    pandoc
    peek
  ];

  home.file."bin/chrome-disabled-web-security" = {
    text = ''
      #!/bin/sh
      exec chromium --disable-web-security --user-data-dir="/tmp/chromium-disabled-ws" --no-sandbox
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

  # override oh-my-posh-theme
  #  home.file.".poshthemes/theme.omp.json".source = ../themes/posh/gruvbox.omp.json;
}

