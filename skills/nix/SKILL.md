---
name: nix
description: >
  General Nix language and tooling guidance. Use when writing nix expressions,
  searching for nix functions or packages, debugging nix builds, or working with
  nixpkgs overlays, overrides, and shell.nix / default.nix files.
  Does NOT cover CI — see the ci-nix skill for nix/ci.nix and GitHub Actions.
user-invocable: false
---

# Nix Language & Tooling

## No Flakes — Use npins

We do not use Nix flakes. Always prefer npins for dependency pinning.

**Why not flakes:**
- Flakes require `experimental-features = nix-command flakes` — they are still experimental.
- `flake.nix` / `flake.lock` bring in a rigid structure that limits how you organise nix files.
- `builtins.getFlake` requires `--impure` for local evaluation.
- Flake inputs are less transparent than explicit pins — harder to audit what commit you're on.

**Use npins instead:**
- Pure, stable, no experimental features needed.
- Single `npins/sources.json` lock file — easy to review in diffs.
- Works with plain `nix-build` and `nix-shell` (no `nix develop` or `nix run`).
- See the `ci-nix` skill for npins setup commands and shim patterns.

**If you encounter a flake-based project:**
- Do NOT add `flake.nix` or suggest flake commands (`nix develop`, `nix run`, `nix flake`).
- If a dependency only provides a `flake.nix`, use its `default.nix` (most flake repos
  include flake-compat) or pin the source via npins and import directly.
- Replace `builtins.getFlake` calls with npins imports — see ci-nix skill for the pattern.

## Finding Nix Functions: noogle.dev

[noogle.dev](https://noogle.dev/) indexes every function in nixpkgs `lib`, `builtins`,
and nixos modules. Use it to discover functions by name, type signature, or description.

### Browsing
- Function pages live at `https://noogle.dev/f/<path>` where path mirrors the attribute path
  with `/` separators. Examples:
  - `https://noogle.dev/f/lib/attrsets/mapAttrs`
  - `https://noogle.dev/f/lib/lists/forEach`
  - `https://noogle.dev/f/builtins/filter`
- Each page shows: type signature, description, inputs, examples, source link.

### Searching from Claude
Noogle search is client-side (no REST API). To look up a function for the user:
1. Use `w3m -dump "https://noogle.dev/f/lib/<category>/<name>"` if you know the path.
2. Otherwise, point the user to noogle.dev and describe what to search for.

### Common lib categories
| Category       | Examples                                         |
|:---------------|:-------------------------------------------------|
| `lib.attrsets`  | `mapAttrs`, `filterAttrs`, `recursiveUpdate`, `genAttrs` |
| `lib.lists`     | `forEach`, `filter`, `map`, `concatMap`, `unique` |
| `lib.strings`   | `concatStringsSep`, `hasPrefix`, `removeSuffix`  |
| `lib.trivial`   | `pipe`, `flip`, `id`, `const`                    |
| `lib.options`   | `mkOption`, `mkEnableOption`, `mkPackageOption`  |
| `lib.modules`   | `mkIf`, `mkMerge`, `mkForce`, `mkDefault`        |
| `lib.sources`   | `cleanSource`, `sourceByRegex`                   |
| `lib.debug`     | `traceVal`, `traceSeq`, `traceValSeqN`          |

## Finding Packages

```bash
# Search available packages by regex on attribute name
nix-env -qaP '.*WHATEVER.*'

# Example: find packages related to "imagemagick"
nix-env -qaP '.*imagemagick.*'

# With nixpkgs pin (no channel required):
nix-env -f '<nixpkgs>' -qaP '.*WHATEVER.*'

# From a specific npins source:
nix-env -f "$(nix-instantiate --eval -E '(import ./npins).nixpkgs')" -qaP '.*WHATEVER.*'
```

When inside `nix-shell` or with a pinned nixpkgs, prefer querying against that
specific version so results match what the project actually uses.

## Debugging Builds

```bash
# Build with verbose output
nix-build default.nix --show-trace

# Evaluate without building (catches expression errors fast)
nix-instantiate default.nix --show-trace

# Evaluate a specific attribute
nix-instantiate default.nix -A myPackage --show-trace

# Enter build environment to debug interactively
nix-shell default.nix -A myPackage
# Then run individual build phases: unpackPhase, configurePhase, buildPhase, etc.

# Inspect a derivation's dependencies
nix-store -qR $(nix-instantiate default.nix -A myPackage)

# Show why a derivation is being built (what changed)
nix-store --diff-closures /nix/store/old-drv /nix/store/new-drv

# Check if something is in the binary cache
nix path-info --store https://cache.nixos.org /nix/store/<hash>-<name>
```

## Writing Derivations

### mkDerivation essentials
```nix
pkgs.stdenv.mkDerivation {
  pname = "my-package";
  version = "1.0";
  src = ./.;
  nativeBuildInputs = [ pkgs.cmake ];  # build-time tools (run on build platform)
  buildInputs = [ pkgs.zlib ];          # libraries linked into the result
  # Don't confuse these two — wrong category causes cross-compilation failures.
}
```

### Common override patterns
```nix
# Override arguments to a package
pkgs.foo.override { enableBar = true; }

# Override derivation attributes
pkgs.foo.overrideAttrs (old: {
  patches = old.patches or [] ++ [ ./my-fix.patch ];
  buildInputs = old.buildInputs ++ [ pkgs.extra-lib ];
})

# Override Haskell package
haskellPackages.foo.overrideAttrs (old: {
  # For Haskell, also consider overrideCabal from callCabal2nix
})
```

### Overlays
```nix
# Apply an overlay to nixpkgs
import nixpkgs-src {
  overlays = [
    (final: prev: {
      myPackage = prev.myPackage.overrideAttrs (old: {
        version = "2.0";
      });
    })
  ];
}
```

## shell.nix Patterns

### Basic development shell
```nix
{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = [
    pkgs.ghc
    pkgs.cabal-install
  ];
  # Set environment variables
  MY_VAR = "value";
  # Run commands on shell entry
  shellHook = ''
    echo "Dev shell ready"
  '';
}
```

### With pinned nixpkgs (prefer this)
```nix
let
  sources = import ./npins;
  pkgs = import sources.nixpkgs {};
in pkgs.mkShell {
  buildInputs = [ pkgs.ghc pkgs.cabal-install ];
}
```

## Language Patterns

### let-in vs with
```nix
# let-in: explicit bindings, preferred for clarity
let
  x = 1;
  y = 2;
in x + y

# with: imports all attrs into scope, use sparingly
# Good: with pkgs; [ git vim ]  (short package lists)
# Bad:  with lib; with builtins; ...  (obscures where names come from)
```

### String interpolation and paths
```nix
# String interpolation (converts to string via toString or outPath)
"${pkgs.hello}/bin/hello"

# Multi-line strings (indentation is stripped)
''
  line one
  line two
  ${variable}
''

# Paths are NOT strings — they get copied to /nix/store
src = ./.;          # copies current dir to store
src = ./my-file;    # copies file to store
# Use builtins.path or lib.sources.cleanSource to control what gets copied
```

### Avoiding common mistakes
- **Infinite recursion**: Using `rec { }` with overlapping references.
  Prefer `let` bindings or `final:prev:` overlay pattern.
- **IFD (import from derivation)**: `import (pkgs.runCommand ...)` blocks
  evaluation until the derivation builds. Avoid in library code.
- **Forgetting `.override` vs `.overrideAttrs`**: `.override` changes the
  arguments passed to the function; `.overrideAttrs` changes the derivation attrs.
- **Using `with` in `buildInputs`**: `buildInputs = with pkgs; [ a b c ];`
  is fine, but `with pkgs;` at file top level makes it hard to tell where
  names come from.

## Haskell Package Overrides

### haskellPackages.override pattern
The standard way to customize Haskell packages in nix (from haskell-template-project):
```nix
pkgs.haskellPackages.override {
  overrides = hnew: hold: {
    my-project = hnew.callCabal2nix "my-project" ../. { };
    # Jailbreak a package (remove all version bounds from .cabal):
    some-pkg = pkgs.haskell.lib.doJailbreak hold.some-pkg;
    # Disable tests:
    other-pkg = pkgs.haskell.lib.dontCheck hold.other-pkg;
  };
}
```

### doJailBreak: what it does and doesn't do
- `doJailBreak` adds `jailbreak = true` to the derivation, which runs
  `jailbreak-cabal` to strip version bounds from the `.cabal` file
- It does **NOT** modify `drv.src` — the source tarball is unchanged
- This means `doJailBreak` only works for packages built through the
  haskellPackages infrastructure (nix derivations)
- For standalone `cabal build` invocations (e.g. cross-compilation pipelines),
  use `--allow-newer` as the cabal-level equivalent

### Common haskell.lib functions
```nix
with pkgs.haskell.lib; {
  # Remove version bounds (equivalent to cabal --allow-newer for this pkg)
  foo = doJailbreak old.foo;
  # Skip test suite
  bar = dontCheck old.bar;
  # Skip haddock
  baz = dontHaddock old.baz;
  # Add extra deps
  qux = addBuildDepends old.qux [ old.extra-dep ];
  # Override cabal attrs directly
  quux = overrideCabal old.quux (drv: {
    configureFlags = drv.configureFlags or [] ++ [ "--flag=foo" ];
  });
}
```

## Cross-Compilation for Android

### Toolchain setup
```nix
# Get cross-compiled package set for Android
androidPkgs = pkgs.pkgsCross.aarch64-android-prebuilt;  # or armv7a-android-prebuilt
ghc = androidPkgs.haskellPackages.ghc;

# armv7a needs profiling disabled (LLVM crashes on profiled libs)
ghc-armv7a = androidPkgs.haskellPackages.ghc.override { enableProfiledLibs = false; };

# Cross-GHC binaries use a target prefix
ghcCmd = "${ghc}/bin/${ghc.targetPrefix}ghc";          # e.g. aarch64-unknown-linux-android-ghc
ghcPkgCmd = "${ghc}/bin/${ghc.targetPrefix}ghc-pkg";
```

### Android SDK/NDK in nix
```nix
pkgs = import nixpkgsSrc {
  config.allowUnfree = true;                    # required for Android SDK
  config.android_sdk.accept_license = true;     # required for Android SDK
};
```

### Static linking for Android
Android can't find GHC's separate shared libraries at runtime.
Use `--whole-archive` to statically link boot libraries into the `.so`:
```bash
ghc -shared -o libapp.so Main.hs \
  -optl-Wl,--whole-archive \
  -optl$RTS_LIB -optl$BASE_LIB ...  \
  -optl-Wl,--no-whole-archive
```

### Cross-compiling Hackage packages
When cross-compiling third-party packages for Android via `cabal build`:
- Hackage tarballs often have tight upper bounds on boot packages
  (base, deepseq, ghc-prim, bytestring) that are too strict for newer GHC
- `doJailBreak` doesn't help — it only affects nix derivation builds,
  not standalone cabal invocations
- Use `--allow-newer=base,deepseq,ghc-prim,bytestring,...` targeted to
  boot packages only (safe because versions are fixed by GHC)
- **Never** use `--allow-newer=all` — too broad, could mask real conflicts

### overrideAttrs for fixing build phases
```nix
# Fix shell issues in install phases (common with pipefail)
derivation.overrideAttrs (old: {
  installPhase = builtins.replaceStrings
    [ "find $out | head -20" ]        # SIGPIPE under pipefail
    [ "find $out | head -20 || true" ] # suppress SIGPIPE
    old.installPhase;
});
```

### GHC package database (.conf) files
When cross-compiling, package configs may need fixing:
- **id/key fields**: Package's own identifier (preserve these)
- **depends field**: Lists dependency unit IDs (may need cleaning)
- After modifying `.conf` files, always run `ghc-pkg --package-db=DIR recache`
- Cabal sub-libraries (e.g. `attoparsec:attoparsec-internal`) produce
  separate `.a` files under `l/SUBLIB/build/` — often missed by install scripts

## The callPackage Pattern

The fundamental idiom in nixpkgs. Understand this before anything else.

```nix
# callPackage auto-injects arguments from pkgs/lib by name:
# my-package.nix
{ stdenv, fetchFromGitHub, zlib }:   # <- these get filled in automatically
stdenv.mkDerivation { ... }

# default.nix
let pkgs = import <nixpkgs> {};
in pkgs.callPackage ./my-package.nix {}
#                                    ^^ override args here if needed
# e.g. pkgs.callPackage ./my-package.nix { zlib = pkgs.zlib-ng; }
```

`callPackage` makes packages composable — each `.nix` file declares its deps
as function args, and the caller auto-fills them from the package set.

## Fetcher Patterns

```nix
# Fetch from GitHub (most common for open-source deps)
src = pkgs.fetchFromGitHub {
  owner = "user";
  repo = "project";
  rev = "v1.0";       # tag, branch, or commit hash
  sha256 = "";        # leave empty first, nix will tell you the correct hash
  # sha256 = lib.fakeSha256;  # alternative placeholder
};

# Fetch a tarball
src = pkgs.fetchurl {
  url = "https://example.com/foo-1.0.tar.gz";
  sha256 = "";
};

# Fetch and unpack a zip/tarball (auto-strips single top-level dir)
src = pkgs.fetchzip {
  url = "https://example.com/foo-1.0.zip";
  sha256 = "";
};

# Fetch a git repo (when you need submodules or specific git features)
src = pkgs.fetchgit {
  url = "https://github.com/user/project.git";
  rev = "abc123";
  sha256 = "";
  fetchSubmodules = true;  # if needed
};
```

**Getting the hash**: Run with empty `sha256 = ""` or `lib.fakeSha256`,
the build will fail and print the correct hash. Copy it in.

## Trivial Builders

Quick ways to create derivations without a full `mkDerivation`:

```nix
# Create a script on PATH
pkgs.writeShellScriptBin "my-tool" ''
  echo "Hello from $0"
  ${pkgs.curl}/bin/curl "$@"
'';

# Create an arbitrary text file in the store
pkgs.writeText "my-config.json" (builtins.toJSON { key = "value"; });

# Run a shell command as a derivation (result is a store path)
pkgs.runCommand "my-output" { nativeBuildInputs = [ pkgs.jq ]; } ''
  echo '{"a":1}' | jq .a > $out
'';

# Combine multiple packages into one (merge their /bin, /lib, etc.)
pkgs.symlinkJoin {
  name = "my-tools";
  paths = [ pkgs.git pkgs.gh pkgs.jq ];
};
```

## Python Packaging

```nix
# Use Python with specific packages (most common pattern)
pkgs.python3.withPackages (ps: [ ps.requests ps.numpy ])
# Note: some packages like piper-tts live at pkgs.piper-tts (top-level),
# not in python3Packages. Use: pkgs.python3.withPackages (_ps: [ pkgs.piper-tts ])

# Build a Python package from source
pkgs.python3Packages.buildPythonPackage {
  pname = "my-pkg";
  version = "1.0";
  src = ./.;
  propagatedBuildInputs = [ pkgs.python3Packages.requests ];
  # propagatedBuildInputs: deps that should also be available to downstream consumers
  # nativeBuildInputs: build-time only (setuptools, wheel, etc.)
  nativeBuildInputs = [ pkgs.python3Packages.setuptools ];
};

# Build a Python application (not importable, just runnable)
pkgs.python3Packages.buildPythonApplication {
  pname = "my-app";
  version = "1.0";
  src = ./.;
  propagatedBuildInputs = [ pkgs.python3Packages.click ];
};
```

## Propagated vs Non-Propagated Inputs

```nix
pkgs.stdenv.mkDerivation {
  # buildInputs: available at build time only
  buildInputs = [ pkgs.zlib ];

  # nativeBuildInputs: build tools that run on the BUILD machine
  # (critical distinction for cross-compilation)
  nativeBuildInputs = [ pkgs.cmake pkgs.pkg-config ];

  # propagatedBuildInputs: also made available to downstream consumers
  # Use for: shared libraries, Python deps, anything a dependent needs at runtime
  propagatedBuildInputs = [ pkgs.openssl ];
};
```

Rule of thumb: if removing a dep from `buildInputs` causes downstream
packages to break, it should be `propagatedBuildInputs` instead.

## Store Management & Garbage Collection

```bash
# Delete old generations and garbage collect (frees disk space)
nix-collect-garbage -d

# Delete generations older than 30 days
nix-collect-garbage --delete-older-than 30d

# Show store path size and dependencies
nix path-info -sS /nix/store/<hash>-<name>

# Show closure size (total size including all deps)
nix path-info -rsSh /nix/store/<hash>-<name>

# Why is this path in the store? (find reverse dependencies)
nix-store --query --referrers /nix/store/<hash>-<name>
```

## Interactive Exploration with nix repl

```bash
# Start a repl with nixpkgs loaded
nix repl '<nixpkgs>'

# Inside the repl:
# Tab-complete to explore: pkgs.python3Packages.<TAB>
# :t expr    — show type
# :p expr    — pretty-print
# :q         — quit
```

## nix-shell Tips

```bash
# Run a single command in a nix-shell without entering interactive mode
nix-shell --run "cabal build"
nix-shell --command "ghci"

# Quick ad-hoc shell with specific packages (no shell.nix needed)
nix-shell -p python3 nodejs git

# Pure shell (no host env leaking in — closer to CI)
nix-shell --pure

# Shell with a specific nixpkgs
nix-shell -I nixpkgs=/path/to/nixpkgs
```

## Binary Cache Configuration

In `/etc/nix/nix.conf` or `~/.config/nix/nix.conf`:
```
# Add extra binary caches (substituters)
substituters = https://cache.nixos.org https://my-cache.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= my-cache.cachix.org-1:XXXX=

# Useful for CI: don't fail if a cache is unreachable
connect-timeout = 5
fallback = true
```

Cachix is the easiest way to set up a project-specific binary cache:
```bash
cachix use my-cache        # adds cache to nix.conf
cachix push my-cache result # push a build result
```

## Docker / Container Quirks

- `/usr/bin/env` may not exist in Nix-based containers. Use `#!/bin/bash`
  instead of `#!/usr/bin/env bash` for shebangs.

## Useful Builtins Reference

| Builtin                  | Purpose                                      |
|:-------------------------|:---------------------------------------------|
| `builtins.readFile`      | Read file contents as string                 |
| `builtins.toJSON`        | Serialize to JSON string                     |
| `builtins.fromJSON`      | Parse JSON string                            |
| `builtins.fetchurl`      | Fetch URL (impure, avoid in derivations)     |
| `builtins.pathExists`    | Check if path exists                         |
| `builtins.currentSystem` | Get system triple (e.g. `x86_64-linux`)      |
| `builtins.trace`         | Print debug message during evaluation        |
| `builtins.map`           | Map over list (prefer `lib.map` or `map`)    |
| `builtins.filter`        | Filter list                                  |
| `builtins.attrNames`     | Get attribute names from set                 |
| `builtins.hasAttr`       | Check if attr exists in set                  |
| `builtins.elem`          | Check if element is in list                  |
| `builtins.concatLists`   | Flatten one level of list nesting            |
| `builtins.mapAttrs`      | Map over attrset values                      |
| `builtins.listToAttrs`   | Convert `[{name; value}]` to attrset         |
