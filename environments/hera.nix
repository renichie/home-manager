
{ config, pkgs, aoePackage, ... }:

{
  # Override specific dotfiles
  # xdg.configFile."myapp/config".source = ./dotfiles/env1-config;

  home.packages = [
    aoePackage # Agent of Empires (aoe) -- tmux session manager for AI coding agents, built with the web dashboard
  ];

  # Agent of Empires web dashboard. Port is not fixed by the tool -- it
  # defaults to 8080 and can be overridden with --port; bound to
  # 127.0.0.1 only (add --host/--remote if you ever need it reachable
  # off-box). Run in the foreground under systemd rather than aoe's own
  # --daemon flag.
  systemd.user.services.aoe-serve = {
    Unit = {
      Description = "Agent of Empires web dashboard";
      After = [ "default.target" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      ExecStart = "${aoePackage}/bin/aoe serve --host 127.0.0.1 --port 8080";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
