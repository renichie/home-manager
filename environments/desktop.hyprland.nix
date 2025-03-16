{ config, pkgs, ... }:

{
  # Enable wayland utilities and Hyperland
  programs.hyperland = {
    enable = true;
    package = pkgs.hyperland;
  };

  # Add dependencies for a Wayland setup
  environment.systemPackages = with pkgs; [
    # Utilities for Wayland
    wayland
    xwayland
    wl-clipboard
    grim    # For screenshots
    slurp   # For region selection
    swaylock  # Screen locker
    mako    # Notifications
    alacritty # Terminal (or your preferred terminal)
    dunst   # Optional: notification daemon
  ];

  # Enable a display manager (GNOME remains usable via GDM)
  services.gnome3 = {
    enable = true;  # GNOME functionality stays available
  };

  # Add a custom script for launching Hyperland (e.g., via GDM session)
  xsession.windowManager.command = "Hyprland";

  # Optional: Set GNOME to remain default for login manager
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Example GNOME-specific tweaks (to keep GNOME settings intact)
  gnome = {
    autoSuspend = true;
    lockScreen = true;
  };

  # Fonts and themes (optional)
  fonts.fonts = with pkgs; [
    noto-fonts
    noto-fonts-emoji
    jetbrains-mono
  ];

  # Ensure Hyperland dependencies are installed
  home.packages = with pkgs; [
    hyprland
    waybar
    rofi
    wofi
    light  # For screen brightness
  ];

  # Optionally, add a session file for GDM to recognize Hyperland
  system.activationScripts.hyperlandSession = {
    text = ''
      mkdir -p ~/.local/share/wayland-sessions
      echo "[Desktop Entry]
      Name=Hyperland
      Comment=A dynamic tiling Wayland compositor
      Exec=Hyprland
      Type=Application
      DesktopNames=Hyprland
      Keywords=tiling;wm;wayland;
      " > ~/.local/share/wayland-sessions/Hyprland.desktop
    '';
  };
}

