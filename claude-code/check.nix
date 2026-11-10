{ sources }:
let
  # The same unfree nixpkgs import and claude-code package as default.nix, so
  # the check runs the binary the image ships.
  pkgs = import sources.nixpkgs { config.allowUnfree = true; };
  claudeCode = import ./package.nix { inherit pkgs; };
  checkout = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.unions [ ../agent-command.sh ../settings.json ];
  };
in
pkgs.runCommand "ci-claude-code"
  {
    nativeBuildInputs = [ pkgs.bash claudeCode pkgs.coreutils pkgs.jq pkgs.python3 ];
  } ''
  bash ${./test}/system-prompt.sh ${checkout}
  bash ${./test}/dangerous-rm.sh ${checkout}
  bash ${./test}/fable-model.sh ${checkout}
  touch $out
''
