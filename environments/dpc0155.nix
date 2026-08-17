{ config, lib, pkgs, ... }:
let
  ubuntuElectron = config._module.args.ubuntuElectron or null;
  
  homeDir = config.home.homeDirectory;

  # Link-Name in ~  ->  Pfad relativ zu ~
  syncSymlinks = {
    "backups" = ".sync/backup-dpc0155/backups";
    "documents" = ".sync/backup-dpc0155/documents";
    "credentials" = ".sync/backup-dpc0155/credentials";
    "efs-dpc0118.bckp.d" = ".sync/backup-dpc0155/backups/efs-dpc0118";
    "notizen" = ".sync/share-notizen";
  };

  teamsForLinuxPackage =
    if ubuntuElectron == null then
      pkgs.teams-for-linux
    else
      ubuntuElectron.wrapCommandPackage {
        package = pkgs.teams-for-linux;
        executable = "teams-for-linux";
        script = ''
          exec ${ubuntuElectron.nixGLCommand} ${pkgs.electron_34}/bin/electron --no-sandbox --use-angle=gl ${pkgs.teams-for-linux}/share/teams-for-linux/app.asar "$@"
        '';
      };
  vscodePackage =
    if ubuntuElectron == null then
      pkgs.vscode
    else
      ubuntuElectron.wrapCommandPackage {
        package = pkgs.vscode;
        executable = "code";
        script = ''
          exec ${ubuntuElectron.nixGLCommand} ${pkgs.vscode}/bin/code --no-sandbox --use-angle=gl "$@"
        '';
      };
in
{
  # TODO: make explicit whitelist work
  # whitelist unfree software
  nixpkgs.config.allowUnfree = true;
  # Environment specific packages
  home.packages = with pkgs; [
    teamsForLinuxPackage
    vscodePackage

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
    gh
    nodejs_22
    maven
    pnpm
    yq
    jq
    bun # needs `export PATH="$HOME/.bun/bin:$PATH"` for global installs

    ### MISC ###
    gimp
    xfce.thunar
    pandoc
    uv
    peek
    ydotool
  ];

  # Syncthing-Ordner: Symlinks nach ~/.sync/<kanonischer-name>/…
  #
  # Bewusst als Aktivierungs-Snippet statt über home.file
  # Preis: home-manager verwaltet sie nicht mit. Ein hier entfernter Eintrag
  # verschwindet nicht beim nächsten Switch -- dann von Hand löschen.
  home.activation.syncSymlinks =
    lib.hm.dag.entryAfter [ "linkGeneration" ] (
      lib.concatStrings (lib.mapAttrsToList (link: target: ''
        if [[ -e "${homeDir}/${link}" && ! -L "${homeDir}/${link}" ]]; then
          echo "[home-manager] ${link} existiert und ist kein Symlink -- übersprungen" >&2
        else
          run ${pkgs.coreutils}/bin/ln -sfn "${homeDir}/${target}" "${homeDir}/${link}"
        fi
      '') syncSymlinks)
    );

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

  # JetBrains Junie CLI -- this host only; there is no nixpkgs package and the
  # tool bundles its own JetBrains Runtime plus a self-updating shim (versions
  # live under ~/.local/share/junie/versions/<version>/, selected by
  # ~/.local/bin/junie). Packaging it as an immutable Nix derivation would fight
  # that updater, since the read-only store could never take a new version in
  # place -- the same tradeoff documented for Copilot CLI in
  # docs/agent-sandboxing.md (COPILOT_AUTO_UPDATE=false).
  #
  # We install once and never again: while you work, the running binary already
  # downloads the next release into ~/.local/share/junie/updates/ and the shim
  # verifies its SHA-256 and swaps it in on the next launch (see
  # ~/.junie/logs/upgrade.log). Re-running the official installer from activation
  # would only duplicate that ~270MB download -- synchronously, so every
  # `home-manager switch` blocks on it. Upgrades are Junie's job; activation just
  # bootstraps a machine whose shim is missing.
  home.activation.installJunieCli =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ -v DRY_RUN ]]; then
        echo "Would install Junie CLI if $HOME/.local/bin/junie is missing"
      elif [[ -x "$HOME/.local/bin/junie" ]]; then
        echo "[home-manager] Junie CLI already installed -- leaving updates to Junie"
      else
        echo "[home-manager] Installing Junie CLI (junie.jetbrains.com/install.sh)..."
        PATH="${pkgs.curl}/bin:${pkgs.unzip}/bin:${pkgs.coreutils}/bin:$PATH" \
          ${pkgs.bash}/bin/bash -c 'curl -fsSL https://junie.jetbrains.com/install.sh | bash' \
          || echo "[home-manager] Junie CLI install failed (offline?) -- continuing" >&2
      fi
    '';

  systemd.user.services.ydotoold = {
    Unit = {
      Description = "ydotool daemon";
      After = [ "default.target" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/rm -f %t/.ydotool_socket";
      ExecStart = "${pkgs.ydotool}/bin/ydotoold --socket-path %t/.ydotool_socket";
      Restart = "on-failure";
      RestartSec = "1s";
    };
  };
}
