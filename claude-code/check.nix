{ sources }:
let
  # The same unfree nixpkgs import as default.nix, so the check runs the
  # claude-code binary the image ships.
  pkgs = import sources.nixpkgs { config.allowUnfree = true; };
  checkout = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.unions [ ../agent-command.sh ../settings.json ];
  };
in
pkgs.runCommand "ci-claude-code"
  {
    nativeBuildInputs = [ pkgs.bash pkgs.claude-code pkgs.coreutils pkgs.jq pkgs.python3 ];
  } ''
  bash ${./test}/system-prompt.sh ${checkout}
  bash ${./test}/dangerous-rm.sh ${checkout}
  touch $out
''
