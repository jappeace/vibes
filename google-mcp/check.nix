{ pkgs }:
let
  googleMcp = import ./. { inherit pkgs; };
  checkout = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.unions [
      ../agent-command.sh
      ../mcp-servers.sh
      ./test
    ];
  };
in
pkgs.runCommand "ci-google-mcp"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
      pkgs.openssl
      pkgs.python3
      googleMcp.binaries
    ];
  } ''
  bash ${checkout}/google-mcp/test/launcher-config.sh ${checkout}
  bash ${checkout}/google-mcp/test/servers.sh ${checkout}
  touch $out
''
