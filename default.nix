# SPDX-FileCopyrightText: 2019 Bitcoin Suisse
#
# SPDX-License-Identifier: LicenseRef-Proprietary
{ stack2nix-output-path ? "custom-stack2nix-output.nix" }:
let
  cabalPackageName = "tzbtc";
  compiler = "ghc865";

  static-haskell-nix = fetchTarball
  "https://github.com/nh2/static-haskell-nix/archive/dafcc1e693c6bd78d317ba21b7a3224e5f852801.tar.gz";

  pkgs = import "${static-haskell-nix}/nixpkgs.nix";

  stack2nix-script = import
    "${static-haskell-nix}/static-stack2nix-builder/stack2nix-script.nix" {
      inherit pkgs;
      stack-project-dir = toString ./.;
      hackageSnapshot = "2019-10-08T00:00:00Z";
    };

  static-stack2nix-builder =
    import "${static-haskell-nix}/static-stack2nix-builder/default.nix" {
      normalPkgs = pkgs;
      inherit cabalPackageName compiler stack2nix-output-path;
    };

  fullBuildScript = pkgs.writeShellScript "stack2nix-and-build-script.sh" ''
    set -eu -o pipefail
    STACK2NIX_OUTPUT_PATH=$(${stack2nix-script})
    export NIX_PATH=nixpkgs=${pkgs.path}
    ${pkgs.nix}/bin/nix-build --no-link -A static_package --argstr stack2nix-output-path "$STACK2NIX_OUTPUT_PATH" "$@"
  '';

in rec {
  static_package = static-stack2nix-builder.static_package;
  inherit fullBuildScript;
}