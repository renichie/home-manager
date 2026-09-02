# Paseo CLI + daemon (https://paseo.sh) -- not in nixpkgs, so we build the
# published npm package ourselves.
#
# `package.json` pins the release and `package-lock.json` is the resolved
# dependency tree; both are generated, do not hand-edit. To bump the version:
#
#   cd pkgs/paseo
#   npm install --package-lock-only --ignore-scripts @getpaseo/cli@<version>
#   nix run nixpkgs#prefetch-npm-deps -- package-lock.json   # -> npmDepsHash
#
# and update `version` plus `npmDepsHash` below.
{ lib
, buildNpmPackage
, nodejs
, python3
, makeWrapper
}:

buildNpmPackage rec {
  pname = "paseo";
  version = "0.7.2";

  # Only the two manifests matter; the actual code comes from the npm registry.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./package.json ./package-lock.json ];
  };

  npmDepsHash = "sha256-pGv7r+fB4erZchO+sxTu5ebVyxMUAMPq8p+1OiwJJXY=";

  # python3 is for node-pty, whose install script falls back to `node-gyp
  # rebuild` once its prebuilt-binary download fails in the sandbox.
  nativeBuildInputs = [ python3 makeWrapper ];

  # There is nothing to compile: this package only pulls in @getpaseo/cli.
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/paseo
    cp -r node_modules package.json $out/lib/paseo/

    # Mirrors the upstream bin/paseo shim, which runs dist/index.js with the
    # DEP0040 (punycode) warning silenced.
    makeWrapper ${nodejs}/bin/node $out/bin/paseo \
      --add-flags "--disable-warning=DEP0040" \
      --add-flags "$out/lib/paseo/node_modules/@getpaseo/cli/dist/index.js"

    runHook postInstall
  '';

  meta = {
    description = "Control plane for coding agents -- CLI and headless daemon";
    homepage = "https://paseo.sh";
    mainProgram = "paseo";
    platforms = lib.platforms.linux;
  };
}
