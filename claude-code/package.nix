{ pkgs }:
# Decision: ship claude-code 2.1.321, the first release with Claude Fable 5.2
# (claude-fable-5-2), ahead of the nixpkgs-unstable channel, which was at
# 2.1.318 on 2026-11-10. manifest.zst.json is a byte copy of the one at nixpkgs
# master c6b34ee43fdd ("claude-code: 2.1.319 -> 2.1.321") and goes through the
# package's own `manifest` argument, so only the binary is downloaded.
# Rejected: pinning nixpkgs to that master commit (no cache guarantee for its
# stdenv, and it would drag opencode and its stopgate lockfile along).
# Drop the override once the nixpkgs pin ships 2.1.321 or newer.
pkgs.claude-code.override {
  manifest = pkgs.lib.importJSON ./manifest.zst.json;
}
