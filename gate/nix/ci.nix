{ sources ? import ../../npins
, pkgs ? import ./pkgs.nix { inherit sources; }
, hpkgs ? import ./hpkgs.nix { inherit pkgs; }
,
}:
let
  src = builtins.path {
    path = ../.;
    name = "claude-gate-src";
    filter = path: _type:
      let base = baseNameOf (toString path);
      in !(builtins.elem base [ "dist-newstyle" "dist" "result" ".git" ]);
  };
in
{
  # The cabal build / library / executable / test derivation.
  native = import ../default.nix { inherit hpkgs; };

  opencode = import ../../opencode/check.nix { inherit pkgs; };

  claude-code = import ../../claude-code/check.nix { inherit sources; };

  google-mcp = import ../../google-mcp/check.nix { inherit pkgs; };

  # Enforce .hlint.yaml across app/src/test as part of CI, pinned to the same
  # nixpkgs as the rest of the toolchain.
  hlint = pkgs.runCommand "ci-hlint"
    {
      nativeBuildInputs = [ pkgs.hlint ];
    } ''
    cd ${src}
    hlint -h .hlint.yaml app src test
    touch $out
  '';
}
