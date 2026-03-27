---
name: error-messages
description: Writing good error messages that help users understand and fix problems. Use when writing error handling code, improving diagnostics, adding user-facing error strings, or reviewing error messages. Also trigger when writing tests that assert error output.
user-invocable: false
---

# Writing Good Error Messages

A good error message answers three questions: **what** went wrong, **why** it happened, and **what to do** about it. An opaque error forces the user to reverse-engineer the problem from internal state they can't see.

## The Three Questions

Every user-facing error message should contain:

1. **What** — what operation failed, in user-facing terms
2. **Why** — the actual cause, using names the user recognizes (not internal hashes, IDs, or codepaths)
3. **How to fix** — an actionable suggestion, even if approximate

### Bad example (real, from cabal Backpack)

```
The following packages are broken because other packages they depend on
are missing. These broken packages must be rebuilt before they can be used.
planned package consumer-0.1.0.0 is broken due to missing package
  framework-0.1.0.0+95RTb42ZWxa9J13cUStM0q
```

Problems:
- `+95RTb42ZWxa9J13cUStM0q` is an internal instantiation hash — the user has no idea what it refers to
- Doesn't say *which signature* needs filling or *which module* would fill it
- "must be rebuilt" gives no guidance on *how* — the user installed the package via nix, so "rebuild" means nothing without context
- The user cannot map this error to any action

### Good example (what it should say)

```
Package consumer-0.1.0.0 requires an instantiated version of
  framework-0.1.0.0 with signature App filled by app-impl-0.1.0.0:App,
  but only the indefinite (uninstantiated) version of framework is installed.

  This typically happens when the library was installed separately (e.g. via
  nix) without the consumer present, so the required instantiation was never
  built.

  To fix: rebuild framework and consumer together in the same cabal project,
  so cabal can create the instantiated version.
```

This answers all three:
- **What**: consumer needs an instantiated version of framework
- **Why**: only the indefinite version is installed, the specific instantiation (App=app-impl:App) was never built
- **How**: rebuild them together

## Rules

### Never expose internal identifiers without explanation

Hashes, unit IDs, generated names — if it's not something the user typed or would recognize, either:
- Translate it to user-facing terms (signature names, module names, package names)
- Show it alongside the human-readable explanation: `framework-0.1.0.0 (instantiation hash: +95RTb42ZWxa9J13cUStM0q)`
- Omit it entirely if it adds no value

### Name the actors

Error messages involving relationships between components should name both sides:
- Bad: `"missing package framework-0.1.0.0+hash"`
- Good: `"consumer-0.1.0.0 requires framework-0.1.0.0 instantiated with App = app-impl-0.1.0.0:App"`

The user needs to know WHO needs WHAT from WHOM.

### Explain the gap between expected and actual state

Many errors boil down to: "I expected X to exist/be true, but found Y instead." Make both sides explicit:
- Bad: `"missing package"`
- Good: `"only the indefinite version is installed, but the instantiated version (with App filled) is needed"`

### Give actionable guidance

Even a rough suggestion is better than silence:
- Bad: `"must be rebuilt"` (how? where? what command?)
- Good: `"rebuild framework and consumer together in the same cabal project"`
- Acceptable: `"try rebuilding the package with its consumers present"`

If multiple fixes are possible, list them. If you don't know the fix, describe what state needs to change.

### Don't assume the user knows your architecture

The user may not know what "Backpack instantiation" means, what a unit ID is, or why packages have hashes. Write the error for someone who knows their own code but not your tool's internals.

## Testing Error Messages

When writing tests for error output:

### Assert the desired behavior, not the current bug

Tests should describe what a good error looks like. If the current error is bad, write assertions for the *improved* error — the test will fail, documenting the problem.

```haskell
-- Assert what a good error should contain:
assertOutputContains "consumer" r           -- which package is broken
assertOutputContains "App" r                -- which signature needs filling
assertOutputContains "instantiat" r         -- explain the mechanism
assertOutputContains "rebuild" r            -- actionable guidance
```

### Beware verbose/debug output polluting assertions

`assertOutputContains "App"` may pass because "App" appears in debug-level output (e.g. a component graph dump), not in the actual error message. Use specific-enough strings that only match the error itself:

- Bad: `assertOutputContains "App" r` — matches debug output too
- Good: `assertOutputContains "instantiated with App" r` — specific to a proper error message
- Good: `assertOutputContains "signature App" r` — unlikely to appear in debug dumps

### Test the full message, not just that it fires

Don't stop at "the error happened." Assert that the error is *useful*:

```haskell
-- Necessary but not sufficient — just checks it errored
assertOutputContains "broken" r

-- The actual value — does the error help the user?
assertOutputContains "signature App" r
assertOutputContains "rebuild" r
```

## Checklist

When writing or reviewing error messages:

- [ ] Would a user unfamiliar with the codebase understand this error?
- [ ] Does it name the entities involved in user-facing terms?
- [ ] Does it explain why the current state is wrong?
- [ ] Does it suggest at least one concrete action?
- [ ] Are internal identifiers (hashes, unit IDs) either explained or hidden?
- [ ] If the error involves a relationship (A needs B), are both A and B named?
