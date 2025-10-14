{
  description = ''
    Home Manager configuration for multiple environments
    '';

  inputs = {
    # Pin the nixpkgs and home-manager versions
    # nixpkgs.url = "github:NixOS/nixpkgs/release-24.11";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      # url = "github:nix-community/home-manager/release-24.11";
      # stay on unstable for now because of nerd-fonts.hack!
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Add the xremap nix-flake input
    xremap-flake.url = "github:xremap/nix-flake";
  };

  outputs = { self, nixpkgs, home-manager, xremap-flake, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # Apply the xremap overlay from xremap-flake
        overlays = [ xremap-flake.overlays.default ];
      };
    in {
      homeConfigurations = {
        DPC0155 = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs;
          modules = [
            ./system/ubuntu.nix
            ./environments/base.nix
            ./environments/dpc0155.nix
            xremap-flake.homeManagerModules.default
            {
              home.username = "ub422";
              home.homeDirectory = "/home/ub422";
              home.stateVersion = "24.11";

              # TODO: probably does not belong here!
              services.xremap.withX11 = true;
              services.xremap.yamlConfig = builtins.readFile ./dotfiles/xremap.config.yaml;
            }
          ];
        };

        HERA = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs;
          modules = [
            ./environments/base.nix
            ./environments/hera.nix
            xremap-flake.homeManagerModules.default
            {
              home.username = "bernd";
              home.homeDirectory = "/home/bernd";
              home.stateVersion = "24.11";

              # TODO: probably does not belong here!
              services.xremap.withX11 = true;
              services.xremap.yamlConfig = builtins.readFile ./dotfiles/xremap.config.yaml;
            }
          ];
        };

        NYX = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs;
          modules = [
            ./environments/base.nix
            ./system/manjaro.nix
            ./environments/nyx.nix
            xremap-flake.homeManagerModules.default
            {
              home.username = "bernd";
              home.homeDirectory = "/home/bernd";
              home.stateVersion = "24.11";

              # TODO: probably does not belong here!
              # services.xremap.withX11 = true;
              services.xremap.enable = true;
              services.xremap.withWlroots = true;
              services.xremap.yamlConfig = builtins.readFile ./dotfiles/xremap.config.yaml;
            }
          ];
        };
      };
    };
}
