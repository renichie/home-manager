{ config, lib, pkgs, ... }:

let
  dotfilesDir = ../dotfiles; # Path to your dotfiles directory
  themefilesDir = ../themes;
  scriptfilesDir = ../scripts;
  vimNixPlugin = pkgs.vimPlugins.vim-nix;
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
    #vim
    bash
    tmux
    oh-my-posh

    ### Git ###
    git
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

    ### UTILITY ###
    fzf
    xsel
    vlc
    keepassxc
    obsidian
    tokei
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
    ".vimrc".source = lib.mkForce "${dotfilesDir}/.vimrc";
    ".ideavimrc".source = "${dotfilesDir}/.vimrc";
    ".tmux.conf".source = lib.mkForce "${dotfilesDir}/.tmux.conf";
    ".gitconfig".source = "${dotfilesDir}/.gitconfig";
    ".gitignore_global".source = "${dotfilesDir}/.gitignore_global";

    # Setting oh-my-posh theme
    #".poshthemes/theme.omp.json".source = "${themefilesDir}/nightowl.omp.json";
    #".poshthemes/theme.omp.json".source = "${themefilesDir}/nordtron.omp.json";
    ".poshthemes/theme.omp.json".source = "${themefilesDir}/pure.omp.json";

  };

  programs.atuin = {
    enable = true;
    enableBashIntegration = true;   # or enableZshIntegration / enableFishIntegration

    settings = {
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

  programs.tmux = {
    enable = true;
    secureSocket = false;
    terminal = "tmux-256color";
    plugins = with pkgs.tmuxPlugins; [
      #yank
      #sensible
      catppuccin
      #gruvbox
    ];
    extraConfig = ''
      set -g default-terminal "tmux-256color"
      set -ag terminal-overrides ",xterm-256color:RGB"
      setw -g pane-base-index 1
      # Load Nord theme
      run-shell "git clone --depth 1 https://github.com/arcticicestudio/nord-tmux.git ~/.tmux/nord-tmux || true"
      run-shell "~/.tmux/nord-tmux/nord.tmux"
    '';
  };

  programs.vim = {
    enable = true;
    extraConfig = lib.mkAfter (builtins.readFile "${dotfilesDir}/.vimrc");
    plugins = with pkgs.vimPlugins; [
      vimNixPlugin
    ];
  };


  home.sessionVariables = {
    EDITOR = "vim";
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
}
