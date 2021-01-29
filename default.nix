{
  sources ? import ./nix/sources.nix,
  system ? builtins.currentSystem,
  overlays ? [],
  crossSystem ? (import sources.nixpkgs {}).lib.systems.examples.musl64,
}:
let
  crossSystem = null;
in let
  rustChannel = "1.49.0";

  inherit (sources) nixpkgs nixpkgs-mozilla cargo2nix;
  pkgs = import nixpkgs {
    inherit system crossSystem;
    overlays =
      let
        rustOverlay = import "${nixpkgs-mozilla}/rust-overlay.nix";
        cargo2nixOverlay = import "${cargo2nix}/overlay";
      in
        [ cargo2nixOverlay rustOverlay ] ++ overlays;
  };

  serverRustPkgs = pkgs.rustBuilder.makePackageSet' {
    inherit rustChannel;
    packageFun = import ./server-cargo.nix;
    workspaceSrc = sources.static-web-server;
  };

  cobaltPkgs = import nixpkgs {
    inherit system;
    crossSystem = null;
    overlays =
      let
        rustOverlay = import "${nixpkgs-mozilla}/rust-overlay.nix";
        cargo2nixOverlay = import "${cargo2nix}/overlay";
      in
        [ cargo2nixOverlay rustOverlay ] ++ overlays;
  };

  cobaltRustPkgs = cobaltPkgs.rustBuilder.makePackageSet' {
    inherit rustChannel;
    packageFun = import ./cobalt-cargo.nix;
    workspaceSrc = sources.cobalt;
  };

in let
  staticSiteContent = pkgs.stdenv.mkDerivation {
    name = "staticSiteContent";
    src = ./static-site;
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out/_site
      cp -r $src ./static-site
      cd static-site
      ${(cobaltRustPkgs.workspace.cobalt-bin {}).bin}/bin/cobalt build \
        -d $out/_site
    '';
  };
in let
  siteServerContainer = pkgs.dockerTools.buildImage {
    name = "positron-static-site";
    config = {
      Cmd = [
        "${(serverRustPkgs.workspace.static-web-server {}).bin}/bin/static-web-server"
        "--root" "${staticSiteContent}/_site"
        "--assets" "${staticSiteContent}/_site/public"
        "--page404" "${staticSiteContent}/_site/404.html"
        "--page50x" "${staticSiteContent}/_site/500.html"
      ];
    };
  };

in let
  rustPkgs = cobaltRustPkgs;
in rec {
  inherit rustPkgs serverRustPkgs siteServerContainer staticSiteContent;

  ci = with builtins; map
    (crate: pkgs.rustBuilder.runTests crate { })
    (attrValues rustPkgs.workspace);

  inherit cobaltRustPkgs;
  cobalt = cobaltRustPkgs.workspace.cobalt {};

  shell = pkgs.mkShell {
    inputsFrom = pkgs.lib.mapAttrsToList (_: crate: crate {}) rustPkgs.noBuild.workspace;
    nativeBuildInputs = with rustPkgs; [ cargo rustc rust-src ] ++
                                       [ (import cargo2nix {}).package ] ++
                                       [ (cobaltRustPkgs.workspace.cobalt-bin {}).bin ] ++
                                       [ (serverRustPkgs.workspace.static-web-server {}).bin ];

    RUST_SRC_PATH = "${rustPkgs.rust-src}/lib/rustlib/src/rust/library";
  };
}
