---
name: ci-nix
description: >
  CI architecture using nix/ci.nix for local testing and GitHub Actions for platform-specific builds.
  Use when setting up CI, adding test jobs, debugging CI failures, or managing nix pins in Nix-based projects.
user-invocable: false
---

# CI Architecture: nix/ci.nix + GitHub Actions

## Core Principle

Heavy lifting happens in `nix/ci.nix` which can be built locally. GitHub Actions
CI is a thin wrapper that calls `nix-build nix/ci.nix` plus platform-specific
jobs that can't run locally (iOS simulator on macOS, etc.).

## Dependency Management: npins

All nix pins go through `npins/` — a single `sources.json` lock file replaces
scattered `fetchTarball`, `fetchGit`, `builtins.getFlake`, and `fetchFromGitHub` calls.

### Setup
```bash
nix-shell -p npins --run "npins init --bare"
# Add pins (--frozen prevents accidental upgrades via npins update):
nix-shell -p npins --run "npins add --frozen github NixOS nixpkgs --at <commit> --name nixpkgs --branch nixos-unstable"
nix-shell -p npins --run "npins add --frozen github owner repo --at <commit> --name mypin --branch main"
```

### Shim pattern for backward-compatible migration

When a pin file (e.g. `nix/pin.nix`) is imported by many consumers, rewrite it
as a thin shim over npins instead of updating every consumer:

```nix
# nix/pin.nix — before: inline fetchTarball; after: one-line shim
import (import ../npins).nixpkgs { config = import ./config.nix; }
```

```nix
# nix/agenix-pin.nix — preserve the { module; package } interface
let tarball = "${(import ../npins).agenix}";
in {
  module = "${tarball}/modules/age.nix";
  package = "${tarball}/pkgs/agenix.nix";
}
```

### Replacing builtins.getFlake

For repos that have flake-compat `default.nix`, replace:
```nix
# Before (requires --impure or experimental flakes):
myFlake = builtins.getFlake "github:owner/repo/<commit>";
# After (pure, no flakes needed):
myFlake-src = (import ../npins).myFlake;
myFlake = import "${myFlake-src}/default.nix";
# Use myFlake.defaultPackage.x86_64-linux for the built package
# Use ${myFlake-src}/path/to/file for source tree paths
```

Note: `builtins.getFlake` lets you interpolate the result directly as a source path
(`${flake}/config/...`), but with npins you need separate `src` and `outputs` bindings.

### Multiple nixpkgs pins

Projects often need different nixpkgs versions (old youtube-dl pin, android studio pin, etc.).
Use descriptive names:
```
nixpkgs            — main pin
nixpkgs-lix        — for lix package from newer nixpkgs
nixpkgs-youtube-dl — old pin where youtube-dl still works
nixpkgs-dbfield    — ancient pin for specific shell
```

## nix/ci.nix Structure

### Monorepo pattern (multiple subprojects + NixOS server eval)

```nix
let
  sources = import ../npins;
  nixpkgs-src = sources.nixpkgs;
  pkgs = import nixpkgs-src { config = import ./config.nix; };

  # Evaluate the full NixOS server configuration.
  # Transitively covers all NixOS-module-only projects.
  nixos-eval = import "${nixpkgs-src}/nixos/lib/eval-config.nix" {
    system = "x86_64-linux";
    modules = [ ./hetzner/configuration.nix ];
  };
in {
  # Standalone project builds
  projects = {
    massapp = (import ../massapp.org/webservice).defaultPackage.x86_64-linux;
    videocut = import ../videocut.org/webservice {};
    blog = import ../blog;
    agdasearch = (import ../agdasearch.com {}).server;
    raster-backend = (import ../raster.click).ghc.backend;
  };

  # NixOS config evaluation (requires git-crypt for encrypted configs)
  hetzner = pkgs.runCommand "hetzner-eval-check" {} ''
    echo "NixOS configuration evaluated successfully"
    echo "System derivation: ${nixos-eval.config.system.build.toplevel.drvPath}"
    touch $out
  '';
}
```

### Single-project pattern (with platform-specific builds)

```nix
{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  };
  isDarwin = builtins.currentSystem == "aarch64-darwin"
          || builtins.currentSystem == "x86_64-darwin";

  runTest = name: testDrv: scriptName:
    pkgs.runCommand "run-${name}" { __noChroot = true; } ''
      ${testDrv}/bin/${scriptName}
      touch $out
    '';
in {
  native = import ../default.nix {};
  android = import ./android.nix { inherit sources; };
  apk = import ./apk.nix { inherit sources; };
  emulator-test = runTest "emulator-test"
    (import ./emulator.nix { inherit sources; }) "test-lifecycle";
} // (if isDarwin then {
  ios = import ./ios.nix { inherit sources; };
  simulator-test = runTest "simulator-test"
    (import ./simulator.nix { inherit sources; }) "test-lifecycle-ios";
} else {})
```

### Key patterns:
- `isDarwin` guard for macOS-only derivations (iOS builds, simulator tests)
- `runTest` wrapper uses `__noChroot = true` for tests needing network/devices
- `__noChroot` requires `--option sandbox relaxed` locally, works in CI where sandbox is off
- Each test is a separate nix derivation importing from `nix/*.nix`

## GitHub Actions CI (.github/workflows/test.yml)

### With npins (no nix_path needed):

```yaml
name: "Test"
on:
  pull_request:
  push:
jobs:
  projects:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v6
    - uses: cachix/install-nix-action@v31
      with:
        extra_nix_config: |
          experimental-features = nix-command flakes
    - name: Nix store cache
      uses: nix-community/cache-nix-action@v6
      with:
        primary-key: nix-${{ hashFiles('npins/sources.json', 'nix/*.nix', '*.cabal') }}
        restore-prefixes-first-match: nix-
    - run: nix-build nix/ci.nix -A projects

  hetzner:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v6
    - uses: cachix/install-nix-action@v31
      with:
        extra_nix_config: |
          experimental-features = nix-command flakes
    - name: Nix store cache
      uses: nix-community/cache-nix-action@v6
      with:
        primary-key: nix-${{ hashFiles('npins/sources.json', 'nix/*.nix', '*.cabal') }}
        restore-prefixes-first-match: nix-
    - name: Unlock git-crypt
      if: "${{ env.GIT_CRYPT_KEY != '' }}"
      run: |
        echo "$GIT_CRYPT_KEY" | base64 -d > /tmp/git-crypt-key
        nix-shell -p git-crypt --run "git-crypt unlock /tmp/git-crypt-key"
        rm /tmp/git-crypt-key
      env:
        GIT_CRYPT_KEY: ${{ secrets.GIT_CRYPT_KEY }}
    - run: nix-build nix/ci.nix -A hetzner
```

**Important**: When using npins, remove the `nix_path` setting from `cachix/install-nix-action`.
npins pins are self-contained — `nix_path` is only needed when nix files use `<nixpkgs>` channel references.

### Platform-specific jobs:

```yaml
  ios:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@v4
    - uses: cachix/install-nix-action@v31
    - name: Nix store cache
      uses: nix-community/cache-nix-action@v6
      with:
        primary-key: nix-ios-${{ hashFiles('npins/sources.json', 'nix/*.nix', '*.cabal') }}
        restore-prefixes-first-match: nix-ios-
    - run: nix-build nix/ios.nix
    - run: nix-build nix/simulator.nix -o result-simulator
    - run: ./result-simulator/bin/test-lifecycle-ios
```

### Guidelines:

1. **Consolidate related tests into base jobs** to avoid spinning up extra runners.
   Only split into separate jobs when tests are expensive or independent.

2. **Use `needs:` for dependent test jobs** so they reuse the nix store cache
   from the base build job (via cachix).

3. **Every CI job should have cancel-on-failure** to save runner minutes:
   ```yaml
   - name: Cancel workflow on failure
     if: failure()
     continue-on-error: true
     run: gh run cancel ${{ github.run_id }}
     env:
       GH_TOKEN: ${{ github.token }}
   ```

4. **Use `nix-community/cache-nix-action@v6`** for nix store caching in GitHub Actions.
   It handles daemon-owned `/nix/store` permissions via sudo and SQLite database merging.
   **Never use `actions/cache` on `/nix/store`** — it cannot write to the daemon-owned
   store (Linux) or read-only APFS volume (macOS SIP), producing thousands of silent
   tar permission errors. Place cache-nix-action AFTER `cachix/install-nix-action`
   so `/nix` exists. Use content-addressed keys:
   `primary-key: nix-${{ hashFiles('npins/sources.json', 'nix/*.nix', '*.cabal') }}`

5. **Upload artifacts on master only** to save storage:
   ```yaml
   - name: Upload APK
     if: github.ref == 'refs/heads/master'
     uses: actions/upload-artifact@v4
   ```

### Error visibility and retry discipline:

6. **Errors must be loud and visible.** When a CI step fails, the actual error
   message (exception, crash reason, missing library) must be printed prominently
   in the output — not buried in a logfile dump. Prefix fatal messages with
   `FATAL:` so retry loops and humans can spot them instantly.

7. **Only retry flaky parts, never deterministic failures.** Retries are for
   transient issues (emulator boot timing, network hiccups). If a failure is
   deterministic (library not found, compilation error, missing dependency),
   detect it and fail immediately instead of burning through N retries:
   ```yaml
   # Bad: retries a fundamentally broken test 10 times
   for attempt in $(seq 1 10); do ./test.sh || sleep 5; done
   # Good: test script detects fatal vs flaky, retry loop respects it
   if grep -q "^FATAL:" "$log_file"; then
       echo "Fatal error — not retrying"; exit 1
   fi
   ```

8. **Always use `set -o pipefail` in CI run blocks that pipe through `tee`.**
   Without it, `cmd | tee log` always returns 0 (from `tee`), silently masking
   failures. GitHub Actions uses `bash -e` by default but does NOT enable
   `pipefail`. This has caused real bugs where broken builds reported success.
   ```yaml
   - name: Run test
     run: |
       set -o pipefail
       ./test.sh 2>&1 | tee test.log
   ```

9. **Test scripts should distinguish fatal from flaky failures.** When a test
   detects an unrecoverable error (e.g. app crashes on startup, native library
   missing), it should print `FATAL: <reason>` and `exit 1` immediately rather
   than continuing through subsequent checks that are guaranteed to fail.
   The outer retry loop greps for `^FATAL:` and stops retrying.

## Local Testing

```bash
# Build everything
nix-build nix/ci.nix

# Build specific attribute
nix-build nix/ci.nix -A projects

# Evaluate without building (fast check that nix expressions are correct)
nix-instantiate nix/ci.nix -A projects

# If HOME is not writable (e.g. in container/CI-like environments):
HOME=/tmp/cabal-home nix-build nix/ci.nix -A projects

# If sandbox blocks __noChroot tests:
nix-build nix/ci.nix --option sandbox relaxed

# Verify npins sources load:
nix-instantiate --eval -E '(import ./npins)'

# Verify a shim works:
nix-instantiate --eval -E '(import ./nix/pin.nix).lib.version'
```

## Common Pitfalls

- **npins add needs --branch**: `npins add github ... --at <commit>` fails without
  `--branch`. Always specify the branch (e.g. `--branch nixos-unstable`, `--branch main`).

- **npins hash mismatch on commit**: Double-check commit hashes when migrating from
  inline pins. A truncated or typo'd hash gives a 404 from GitHub.

- **builtins.getFlake replacement**: The npins source path and flake outputs are separate
  values. You need `src` for file paths and `import "${src}/default.nix"` for flake outputs.

- **Git-crypt in CI**: NixOS server configs that import encrypted files will fail evaluation
  without `git-crypt unlock`. Use a conditional step with a `GIT_CRYPT_KEY` secret.
  This failure is expected when the secret isn't configured.

- **Polling-based tests**: When checking logs for repeated values (e.g., counter
  going 0 -> 1 -> 2 -> 1 -> 0), wait for the Nth occurrence, not just any match.

- **`__noChroot` on sandboxed nix**: Local nix with `sandbox = true` rejects
  `__noChroot`. Use `--option sandbox relaxed` or build individual derivations
  without the `runTest` wrapper.

- **macOS-only derivations on Linux**: `nix-instantiate` will fail for iOS/simulator
  derivations on Linux. This is expected. `ci.nix` uses the `isDarwin` guard to
  skip these automatically.

- **Flaky Windows `ghc-pkg` permission errors**: On GitHub Actions Windows runners,
  `ghc-pkg` can fail with `you don't have permission to modify this file` on the
  package cache during the install step — even though compilation succeeded. This is
  a transient file-locking issue, not a real build failure. Check the actual error
  before assuming a dependency is broken. A single Windows job failing while all other
  platforms pass is a strong signal of flakiness.

- **`cmd | tee` swallows exit codes**: In GitHub Actions `run:` blocks, bash uses
  `set -e` but NOT `set -o pipefail`. So `./test.sh | tee log` returns 0 even when
  `test.sh` fails — `tee` succeeds and that's all bash checks. Always add
  `set -o pipefail` at the top of any run block that pipes output. This bug silently
  passed broken builds in production (prrrrrrrrr PR #35: emulator test failed on every
  check but CI reported success because the exit code came from `tee`).
