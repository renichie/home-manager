{ config, lib, pkgs, ... }:

let
  ubuntuElectron = config._module.args.ubuntuElectron or null;
  
  dotfilesDir = ../dotfiles; # Path to your dotfiles directory
  themefilesDir = ../themes;
  poshThemesDir = ../themes/posh;
  scriptfilesDir = ../scripts;
  vimNixPlugin = pkgs.vimPlugins.vim-nix;

  obsyncPackage = pkgs.writers.writePython3Bin "obsync"
    { flakeIgnore = [ "E265" "E501" ]; }
    (builtins.readFile "${scriptfilesDir}/obsync.py");

  obsyncCompletion = ''
    _obsync_completions() {
      local cur prev words cword
      _init_completion || return

      local features="vim theme appearance snippets hotkeys core-plugins community-plugins daily-notes templates graph app-settings bookmarks canvas backlink page-preview command-palette all sensible"
      local opts="--list --interactive --dry-run -l -i -n"

      case "$prev" in
        --list|-l)
          return
          ;;
      esac

      if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return
      fi

      # Count positional (non-option) args already present
      local positionals=0
      local i
      for ((i=1; i<cword; i++)); do
        local w="''${words[i]}"
        case "$w" in
          --list|-l|--interactive|-i|--dry-run|-n) ;;
          -*) ;;
          *) ((positionals++)) ;;
        esac
      done

      case $positionals in
        0|1)
          # source / target: complete directories
          _filedir -d
          ;;
        *)
          # feature names (allow repeating)
          COMPREPLY=( $(compgen -W "$features" -- "$cur") )
          ;;
      esac
    }

    complete -F _obsync_completions obsync
  '';

  obsidianPackage =
    if ubuntuElectron == null then
      pkgs.obsidian
    else
      ubuntuElectron.wrapCommandPackage {
        package = pkgs.obsidian;
        executable = "obsidian";
        script = ''
          exec ${ubuntuElectron.nixGLCommand} ${pkgs.electron_34}/bin/electron --no-sandbox --use-angle=gl ${pkgs.obsidian}/share/obsidian/app.asar "$@"
        '';
      };
in
{
  # this should always be overwritten!
  #home.username = "base";
  #home.homeDirectory = "/home/base";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.11"; # Please read the comment before changing.

  home.packages = with pkgs; [
    # base packages -- define here what should be in every overlay
    bash
    tmux
    oh-my-posh
    # vim
    neovim

    ### Git ###
    git
    difftastic
    git-lfs
    git-credential-manager

    ### THEMING / FONTS ###
    # only works in unstable as of now -- might need to switch to stable release at some point or fix!
    nerd-fonts.hack
    # nerdfonts.hack

    ### SHORTCUTS ###
    xremap

    ### BACKUP ###
    syncthing

    obsyncPackage

    ### UTILITY ###
    fzf
    xsel
    wl-clipboard
    vlc
    keepassxc
    obsidianPackage
    tokei
    ripgrep
    ripgrep-all
    glow # markdown renderer
    mdformat
    curl
    unzip # required by the Junie CLI installer, see home.activation.installJunieCli below

    ### DIAGRAMS ###
    graphviz
    jdk
    plantuml

    ### UI ###
    redshift
  ];


  # whitelist unfree software
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (pkgs.lib.getName pkg) [
      "obsidian" "vscode"
    ];

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
  programs.bash.enable = true;
  programs.fzf.enable = true;

  # might need to migrate this to environment configs at some point
  home.file = {
    ".bashrc".source = lib.mkForce "${dotfilesDir}/.bashrc";
    ".bash_aliases".source = lib.mkForce "${dotfilesDir}/.bash_aliases";

    # bash-preexec: required by atuin on bash to record commands + cwd.
    # Must be sourced before `atuin init bash` in .bashrc (directory search
    # depends on this hook firing). Exposed at a stable path so the static
    # .bashrc can source it without referencing a nix store path.
    ".local/share/bash-preexec.sh".source =
      "${pkgs.bash-preexec}/share/bash/bash-preexec.sh";

    # AI agent sandbox wrapper (bubblewrap-based)
    ".local/bin/agent-sandbox.sh" = {
      source = "${scriptfilesDir}/agent-sandbox.sh";
      executable = true;
    };
    ".vimrc".source = lib.mkForce "${dotfilesDir}/.vimrc";
    ".config/nvim/init.vim".source = lib.mkForce "${dotfilesDir}/init.vim";
    ".ideavimrc".source = "${dotfilesDir}/.vimrc";
    ".tmux.conf".source = lib.mkForce "${dotfilesDir}/.tmux.conf";
    ".gitconfig".source = "${dotfilesDir}/.gitconfig";
    ".gitignore_global".source = "${dotfilesDir}/.gitignore_global";
    ".lesskey".source = "${dotfilesDir}/.lesskey";

    # obsync bash completion
    ".local/share/bash-completion/completions/obsync".text = obsyncCompletion;

    # Setting oh-my-posh theme
    #".poshthemes/theme.omp.json".source = lib.mkDefault "${poshThemesDir}/nightowl.omp.json";
#    ".poshthemes/theme.omp.json".source = lib.mkDefault "${poshThemesDir}/nordtron.omp.json";
    ".poshthemes/theme.omp.json".source = lib.mkDefault "${poshThemesDir}/pure.omp.json";
    #".poshthemes/theme.omp.json".source = lib.mkDefault "${poshThemesDir}/config.omp.json"; # non-functional

  };

  programs.atuin = {
    enable = true;
#    enableBashIntegration = true;   # or enableZshIntegration / enableFishIntegration

    settings = {
      auto_sync = true;
      sync_frequency = "10s";
      search_mode = "fuzzy";

      # Make matches feel “fzf-ish”
      # prefer_exact_match = true;
      prefer_exact = true;
      smart_case = true;

      # Optional quality-of-life
      style = "compact";
      keymap = "vim-normal"; 
    };
  };


  programs.vim = {
    enable = true;
    extraConfig = lib.mkAfter (builtins.readFile "${dotfilesDir}/.vimrc");
    plugins = with pkgs.vimPlugins; [
      vimNixPlugin
    ];
  };


  home.sessionVariables = {
    EDITOR = "nvim";
    GRAPHVIZ_DOT = "${pkgs.graphviz}/bin/dot";
  };

  fonts.fontconfig.enable = true;

  # Define Syncthing as a user systemd service
  systemd.user.services.syncthing = {
    Unit = {
      Description = "Syncthing file synchronization service";
      after = [ "network.target.service" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      ExecStart = "${pkgs.syncthing}/bin/syncthing -no-browser -home=${config.home.homeDirectory}/.config/syncthing";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  services.redshift = {
    enable = true;

    # Location: manual coordinates
    provider = "manual";        # or "geoclue2" if you have geoclue set up
    latitude = 48.1;
    longitude = 11.6;

    temperature = {
      day = 6500;
      night = 3000;
    };

    # Optional: more aggressive night tint
    # temperature.night = 2700;

    settings.redshift = {
      brightness-day = 1.0;
      brightness-night = 0.8;
    };

  };

  # JetBrains Junie CLI has no nixpkgs package and bundles its own JetBrains
  # Runtime + self-updating shim (installed versions live under
  # ~/.local/share/junie/versions/<version>/, selected by ~/.local/bin/junie).
  # Packaging it as an immutable Nix derivation would fight that updater (the
  # Nix store is read-only, so it could never write a new version in place)
  # -- the same tradeoff already documented for Copilot CLI in
  # docs/agent-sandboxing.md (COPILOT_AUTO_UPDATE=false). Instead, run the
  # official installer on `home-manager switch`, but only when a newer
  # version is actually available: the installer itself always
  # re-downloads/overwrites regardless of what's installed (no version check
  # of its own), so calling it unconditionally on every switch would re-fetch
  # the ~200MB release archive every time. We instead do a cheap pre-check
  # against the small public update-info manifest and skip the installer
  # entirely when the locally installed version already matches the latest
  # one for our platform.
  home.activation.installJunieCli =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [[ -v DRY_RUN ]]; then
        echo "Would check/install/update Junie CLI (junie.jetbrains.com/install.sh)"
      else
        PATH="${pkgs.curl}/bin:${pkgs.unzip}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:$PATH" \
          ${pkgs.bash}/bin/bash -c '
            set -uo pipefail

            junie_data="$HOME/.local/share/junie"
            current_link="$junie_data/current"
            update_info_url="https://raw.githubusercontent.com/jetbrains-junie/junie/main/update-info.jsonl"

            installed_version=""
            if [[ -L "$current_link" ]]; then
              installed_version="$(basename "$(readlink -f "$current_link" 2>/dev/null)" 2>/dev/null)"
            fi

            os_name="" arch_name=""
            case "$(uname -s)" in
              Linux)  os_name="linux" ;;
              Darwin) os_name="macos" ;;
            esac
            case "$(uname -m)" in
              x86_64|amd64)  arch_name="amd64" ;;
              aarch64|arm64) arch_name="aarch64" ;;
            esac
            platform="''${os_name}-''${arch_name}"

            latest_version=""
            if [[ -n "$os_name" && -n "$arch_name" ]]; then
              latest_version="$(curl -fsSL "$update_info_url" 2>/dev/null \
                | grep "\"platform\":\"$platform\"" | tail -1 \
                | sed -n "s/.*\"version\":\"\([^\"]*\)\".*/\1/p")"
            fi

            if [[ -n "$installed_version" && -n "$latest_version" && "$installed_version" == "$latest_version" ]]; then
              echo "[home-manager] Junie CLI already up to date ($installed_version)"
            else
              echo "[home-manager] Installing/updating Junie CLI (''${installed_version:-none} -> ''${latest_version:-latest})..."
              curl -fsSL https://junie.jetbrains.com/install.sh | bash
            fi
          ' || echo "[home-manager] Junie CLI install/update check failed (offline?) -- continuing" >&2
      fi
    '';
}
