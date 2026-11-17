{ pkgs, sources, claudeGate }:
let
  package = pkgs.lib.importJSON ./package.json;
  opencode = import ./package.nix { pkgs = import ./nixpkgs.nix { inherit sources; }; };
  # Decision: typecheck against the published SDK matching the image's OpenCode
  # version, with npm integrity hashes imported into Nix. Handwritten API stubs
  # would hide upstream changes; type-only imports need no runtime dependencies.
  nodeModules = pkgs.importNpmLock.buildNodeModules {
    inherit package;
    packageLock = pkgs.lib.importJSON ./package-lock.json;
    nodejs = pkgs.nodejs;
    derivationArgs.npmFlags = [ "--ignore-scripts" ];
  };
  source = pkgs.lib.cleanSourceWith {
    src = ./.;
    filter = path: _type: baseNameOf path != "node_modules";
  };
in
assert package.devDependencies."@opencode-ai/plugin" == opencode.version;
assert package.devDependencies."@opencode-ai/sdk" == opencode.version;
pkgs.runCommand "ci-opencode-stopgate"
  {
    nativeBuildInputs = [ pkgs.nodejs opencode pkgs.coreutils pkgs.tmux ];
    CLAUDE_GATE_TEST_BINARY = "${claudeGate}/bin/claude-gate";
    OPENCODE_TEST_NODE_MODULES = "${nodeModules}/node_modules";
  } ''
  cp -r ${source} opencode
  chmod -R u+w opencode
  ln -s ${nodeModules}/node_modules opencode/node_modules
  cd opencode
  npm run typecheck
  npm test
  node --test test/server-smoke.js test/system-prompt.js test/skill-autocomplete.js
  touch $out
''
