{ pkgs }:
let
  checkout = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.unions [
      ../agent-command.sh
      ../claude-code/test/fixture.sh
      ../claude-code/test/recording_provider.py
    ];
  };
in
pkgs.runCommand "ci-opencode"
  {
    nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.git pkgs.jq pkgs.opencode pkgs.python3 ];
  } ''
  bash ${./test}/instructions.sh ${checkout}
  touch $out
''
