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
