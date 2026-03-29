---
name: haskell-project
description: >
  Haskell project conventions based on jappeace/haskell-template-project.
  Use when creating new Haskell projects, adding cabal stanzas, configuring nix,
  setting up CI, or working on any Haskell codebase that follows the template pattern.
  Also use when the user asks to start or scaffold a new Haskell project.
user-invocable: false
---

# Haskell Project Conventions

Based on [jappeace/haskell-template-project](https://github.com/jappeace/haskell-template-project).
Always refer to the live template files below as the source of truth — they may have
been updated since this skill was written.

## Live Template Files

### template.cabal
```cabal
!`gh api repos/jappeace/haskell-template-project/contents/template.cabal --jq .content | base64 -d`
```

### shell.nix
```nix
!`gh api repos/jappeace/haskell-template-project/contents/shell.nix --jq .content | base64 -d`
```

### default.nix
```nix
!`gh api repos/jappeace/haskell-template-project/contents/default.nix --jq .content | base64 -d`
```

### nix/pkgs.nix
```nix
!`gh api repos/jappeace/haskell-template-project/contents/nix/pkgs.nix --jq .content | base64 -d`
```

### nix/hpkgs.nix
```nix
!`gh api repos/jappeace/haskell-template-project/contents/nix/hpkgs.nix --jq .content | base64 -d`
```

### app/Main.hs
```haskell
!`gh api repos/jappeace/haskell-template-project/contents/app/Main.hs --jq .content | base64 -d`
```

### src/Template.hs
```haskell
!`gh api repos/jappeace/haskell-template-project/contents/src/Template.hs --jq .content | base64 -d`
```

### test/Test.hs
```haskell
!`gh api repos/jappeace/haskell-template-project/contents/test/Test.hs --jq .content | base64 -d`
```

### makefile
```makefile
!`gh api repos/jappeace/haskell-template-project/contents/makefile --jq .content | base64 -d`
```

### .ghci
```ghci
!`gh api repos/jappeace/haskell-template-project/contents/.ghci --jq .content | base64 -d`
```

### .hlint.yaml
```yaml
!`gh api repos/jappeace/haskell-template-project/contents/.hlint.yaml --jq .content | base64 -d`
```

### .stylish-haskell.yaml
```yaml
!`gh api repos/jappeace/haskell-template-project/contents/.stylish-haskell.yaml --jq .content | base64 -d`
```

### .gitignore
```
!`gh api repos/jappeace/haskell-template-project/contents/.gitignore --jq .content | base64 -d`
```

### .github/workflows/ci.yaml
```yaml
!`gh api repos/jappeace/haskell-template-project/contents/.github/workflows/ci.yaml --jq .content | base64 -d`
```

### .github/workflows/bump.yaml
```yaml
!`gh api repos/jappeace/haskell-template-project/contents/.github/workflows/bump.yaml --jq .content | base64 -d`
```

## How to Apply These Conventions

### Key Principles

1. **Library-centric**: all real code goes in `src/` as library modules. The executable
   in `app/Main.hs` is a trivial wrapper (`import qualified MyLib; main = MyLib.main`).
   Tests import the library.

2. **Common stanza**: extensions, warnings, and base dependency are declared once in
   `common common-options` and imported by all components. Copy the exact set from the
   template cabal file above.

3. **Strict warnings**: `-Wall -Werror -Wunused-packages` etc. All warnings are errors.
   Exe and test stanzas add `-Wno-unused-packages` to suppress false positives.

4. **Nix dependency chain**: `npins/ -> nix/pkgs.nix -> nix/hpkgs.nix -> shell.nix / default.nix`.
   Uses `callCabal2nix` in `hpkgs.nix` overlay. No flakes.

5. **Dev speed**: makefile overrides `-O2` with `-O0` for fast builds. `.ghci` uses
   `-fobject-code -O0` for fast reloads. `ghcid` runs tests on save.

6. **Dual CI**: nix build on ubuntu + cabal matrix across GHC versions and OSes.
   Both cancel the workflow on first failure.

7. **Test framework**: always `tasty` + `tasty-hunit`. Add `tasty-quickcheck` if
   properties make sense. Test suite is always named `unit`.

### Creating a New Project

When scaffolding a new Haskell project:

1. Create directory structure: `src/`, `app/`, `test/`, `nix/`, `cbits/` (if C)
2. Copy and adapt each template file above, replacing `template` with the project name
3. Set up npins: `nix-shell -p npins --run "npins init --bare && npins add --frozen channel nixpkgs-unstable --name nixpkgs"`
4. Note: `hpkgs.nix` uses a nix name (e.g. `my-project`) that may differ from the cabal package name
5. Verify: `nix-build` and `nix-shell --run "cabal test"`

**IMPORTANT — Repository setup**: New projects get their **own repository**. Do NOT
open a PR back to `jappeace/haskell-template-project`. Instead:

1. Create a new repo: `gh repo create <owner>/<project-name> --public`
2. Initialize git locally, commit the scaffolded code
3. Push to the new repo's `master` branch
4. For subsequent feature work, branch from master and open PRs against the new repo

### Sub-libraries (when needed)

```cabal
library my-sub-lib
  import: common-options
  exposed-modules: My.Sub.Module
  hs-source-dirs: src-sub
  visibility: public    -- required for external consumers
```
