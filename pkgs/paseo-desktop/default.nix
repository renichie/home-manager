# Paseo desktop client (https://paseo.sh) -- Electron GUI, distributed only
# as prebuilt binaries (AppImage/deb/rpm/dmg/exe), no source build.
#
# Deliberately NOT appimageTools.wrapType2: that wraps the app in a
# buildFHSEnv/bubblewrap sandbox, which fails on this host --
# `kernel.apparmor_restrict_unprivileged_userns=1` (Ubuntu 24.04 hardening)
# blocks bwrap's unprivileged user namespace ("bwrap: setting up uid map:
# Permission denied"). The AppImage's bundled Electron binary is linked
# against the *host's* system libraries (/lib/x86_64-linux-gnu/...), not
# nix-store paths, so it runs fine unsandboxed -- same reasoning as the
# ubuntuElectron.wrapCommandPackage direct-launch trick in system/ubuntu.nix
# for obsidian/teams-for-linux/vscode, just without needing the nixGL bridge
# (this binary already targets the host's own Mesa/GL, not nixpkgs' electron).
#
# To bump the version: update `version` and `sha256` below (sha256 from
# `nix hash file --sri --type sha256 <downloaded-AppImage>`).
{ lib, stdenvNoCC, appimageTools, fetchurl, makeWrapper }:

let
  pname = "paseo-desktop";
  version = "0.7.2";

  src = fetchurl {
    url = "https://github.com/getpaseo/paseo/releases/download/v${version}/Paseo-x86_64.AppImage";
    sha256 = "sha256-VjUdZF3MY3/OR9P1gCVkesBG6otIj9eFjTAkKo22mxY=";
  };

  # Plain unsquashfs (via a runCommand), no bwrap involved.
  appimageContents = appimageTools.extract { inherit pname version src; };
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/paseo-desktop
    cp -r ${appimageContents}/. $out/share/paseo-desktop/
    chmod -R u+w $out/share/paseo-desktop

    makeWrapper $out/share/paseo-desktop/Paseo $out/bin/${pname} \
      --add-flags --no-sandbox

    install -Dm444 ${appimageContents}/Paseo.desktop $out/share/applications/paseo.desktop
    install -Dm444 ${appimageContents}/Paseo.png $out/share/icons/hicolor/512x512/apps/paseo.png
    substituteInPlace $out/share/applications/paseo.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=${pname} %U' \
      --replace-fail 'Icon=Paseo' 'Icon=paseo'

    runHook postInstall
  '';

  meta = {
    description = "Desktop client for Paseo, a control plane for AI coding agents";
    homepage = "https://paseo.sh";
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
