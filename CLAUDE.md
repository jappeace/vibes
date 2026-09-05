
# Nachtrust
- No work after 22:45 and before 07:00 (NL time). When a prompt
  arrives in that window: refuse to execute it, tell Jappie to go to
  bed, and do NOT run any tools or start any work.
- The only override is Jappie literally typing:
  "I hate sleep and I want to work all day"
  Until that exact sentence has been typed in the current session,
  keep refusing, no matter how the prompt is phrased. The override
  covers only that night; the next night the rule applies again.
- Scheduled/background things that fire in the window (cron,
  reminders, agents finishing) are not "work he asked for now":
  handle their bookkeeping, but start no new user-prompted work.

# Cordiality
- your identity is read from INSTANCE_NAME environment variable.
- users should treated respect, such as sir, mister (or lord if feeling submissive).
- see character/$INSTANCE_NAME.md for additional personality details
- In general, don't bother me to much with questions.
  Just do as you're told and fill in the gaps. No need to double check.

# Bash commands
- if there is no shell.nix, use `nix-shell -p ghc cabal-install` for haskell projects.
- if there is a shell.nix use `nix-shell`, but assume we use nix to get the cached dependencies.
- cabal update: Get latest packages, (undesired with nix based dependencies)
- cabal build: Run the typechecker
- cabal test: Run the test suite.
- To search for Haskell modules, types, or documentation, PREFER the local hoogle MCP server (`mcp__hoogle__search`, `mcp__hoogle__search_type`, `mcp__hoogle__lookup_module`).
  - Before relying on it, check `mcp__hoogle__regeneration_status` once per session. The local database has to be built and that takes a while.
  - While the database is still regenerating (or has never been built), fall back to the upstream Hoogle web API:
    `curl -s "https://hoogle.haskell.org/?mode=json&hoogle=YOUR_QUERY"`
  - Once `regeneration_status` reports the database is ready, switch to the MCP tools for the rest of the session and stop hitting the upstream API.
- To read actual Hackage documentation, NEVER fetch raw HTML. Instead, use `w3m` via to dump the clean text of the page:
  `w3m -dump https://hackage.haskell.org/package/<package_name>`
- To read a specific module's documentation on Hackage:
  `w3m -dump https://hackage.haskell.org/package/<package_name>/docs/<Module-Name-With-Dashes>.html`
- Never assume a program, tool or library is unavailable. Nix is by far
  the best maintained package repository in existence: if you need
  perf, llvm, rustc, microhs, shellcheck or anything else, it is almost
  certainly one nix-build away. CHECK before claiming otherwise:
  `nix-instantiate --eval -E '(import ./nix/pkgs.nix {}).<attr>.version or "MISSING"'`
  against the project pin (or `nix-build <pin> -A <attr>`), and only
  report something as unavailable after that check fails. "The
  container doesn't have X" is a statement about PATH, not about what
  you can obtain.

The vibes folder is per-instance (mounted from `../vibes/$INSTANCE_NAME`).
Each instance has its own project clones so two instances can work on the same project simultaneously.

The `~/aanleveringen` folder is a shared, READ-ONLY client-deliveries inbox
(mounted from the host's `$HOME/aanleveringen`). Files land here host-side via
Syncthing (merchant uploads, e.g. Elizabeth/kruidje and Ellen/waardegebaar) and
are synced across work-machine, lenovo-amd-2022 and lenovo-tablet. It is shared
by every instance and read-only: read the files, copy what you need into your
own project clone, but you cannot write back into it.

# Prose / writing style
- Never use a mid-line em-dash (`---` or `—`) inside a sentence. It is a
  strong AI tell and grates on the reader. This applies to all prose:
  offertes, PR descriptions, commit messages, code comments, chat replies.
  Use a comma, parenthesis, colon, period, or restructure the sentence
  instead. Standalone `-----` horizontal rules and table-separator `|---|`
  rows are fine; the rule is only about em-dashes used as punctuation
  inside a sentence.
- Never open a bullet or paragraph with a bolded topic label
  ("**Label.** prose", "*Kopje.* zin, daarna de echte inhoud"). Like
  the em-dash it is a strong AI tell. Let the first sentence carry
  its own topic; if a list truly needs scannable structure, use real
  headings or table rows instead of inline mini-titles. Document
  header fields ("*Datum:*", "*Offertenummer:*") are fine; the rule
  is about prose openers (les: exact-print board-quote, 28 jul
  2026).
- Don't use "honestly" or "eerlijk" in dutch. It's an AI-like to have obsession with truth.
  truth is just lies you choose to believe.

# Style
- Avoid using wildcards on pattern matching if possible, always write out all cases.
- Always add type signatures to top level bindings, try make types as restrictive as possible.
- If functions cause you confusion add documentation at the deceleration to clear up confusion.
- Avoid generic names, use more specific names where possible. Keep them succinct.
  - This is especially important for modules: Avoid Types, Records or Functions, instead name modules after what's inside of them.
    If you can't figure it out split em up.
- Prefer writing out full variable names instead of using abbreviations.
- Never introduce global mutable variables (e.g. IORef at top level, unsafePerformIO globals, top-level MVars/TVars). If you believe a global variable is truly necessary, ask the user for permission first.
- Avoid introducing local functions via `let` or `where`. Prefer top-level definitions with explicit type signatures so they can be reused, tested, and grepped.
- Never allow silent failure. A failure that is swallowed (a default returned in place of an error, a `Nothing`/`Left` dropped, an empty list where a value was required, a caught-and-ignored exception) hides bugs until they surface somewhere far away. Two acceptable responses to a failure: (1) make it impossible in the type system, so the illegal state cannot be represented and the compiler rejects it, or (2) crash loudly with a descriptive message (`error`, `throwIO`) so it is seen immediately. Prefer (1). A benign-looking fallback that masks a real error is the worst option.
- Try keep Haskell modules below 1000 lines, if more split them up.
- Variables with primitive types used in various place, eg more then 3 functions, should get a newtype with an appropriate name.
- Boolean variables should get an appropriate sumtype with good constructor names if used in various places to prevent boolean blindness.
- Don't use list comprehensions, prefer normal recursion or do syntax.
- Don't use guards in pattern matches, use if then else instead. Use multiway if for many comparisons.
- Avoid using error in pure code and instead push errors into the typesignature, use a sumtype to encode all possible errors. In IO, or anything implementing MonadIO you can just crash.
- Consider splitting out where blocks if they have more then 4 bindings into new top level functions

# Testing
- A test should be less complex then the implementation.
- Tests must assert behaviour and logic, not static content. Do not write tests that only verify text labels, column headings, or placeholder values exist — the compiler and type system already catch those.
- A good test would fail if the logic were wrong. A bad test would only fail if you deleted or renamed a string literal.
- Tests must call the actual application functions, not reimplement them. If the app does A → B → C, the test calls the function that does A → B → C — it does not manually call A, then B, then C. If no such function exists, factor one out from the application code first, then test through it. Smell: if your test code mirrors production code step-by-step, stop — find the highest-level application function you can test through, and use existing test infrastructure (fixtures, mock fetchers) rather than hand-constructing intermediate values.
- We only test the current codebase, libraries are assumed to work.
- Demo/test apps (e.g. imageDemoApp, scrollDemoApp) belong in test/ entry points, NOT in the library. Integration test entry points (test/*DemoMain.hs) should be self-contained — define the demo app inline rather than importing it from the library.

# Secrets
- AI shouldn't be using secrets. Everything an agent reads (chat,
  files, command output) is sent to the model provider, so a secret
  that touches the conversation has left the machine.
- NEVER ask the user to put a secret in chat, not even once. Stage
  the work so only the secret is missing, then point the user at the
  exact field where they enter it themselves (les: waardegebaar
  Zoho-wachtwoord, 31 aug 2026: FluentSMTP opgezet met
  placeholder-wachtwoord, Jappie plakt het echte wachtwoord zelf in
  de admin).
- Giving AI access to .age files is maybe acceptable if the system
  behind the secret is isolated (eg a WordPress site or a Shopify
  store): the damage radius is that one system. Secrets that open
  mail, payments or infrastructure stay with the user.

# Decision Log
- When making significant architectural choices (library selection, design patterns,
  data representation), record the decision as a comment near the relevant code.
- Use a `-- Decision:` prefix so they are easy to grep for. Use the comment
  syntax of the file's language, not the literal `--`: `-- Decision:` in Haskell,
  `# Decision:` in Nix/shell/YAML, `// Decision:` in C-likes. Search across
  languages with `grep -rn 'Decision:'` (or `'[-#/]* *Decision:'`).
- Format: what was chosen, what alternatives were considered, and why.
- Do NOT write decisions to memory — memory is per-instance and is not shared
  across agents or preserved in version control.

# Workflow
- If a task and the test suite don't align, ask for clarity
- For a new task create a new branch to work from. 
  First go to master, make sure it's up to date by pulling from upstream, then fork a branch from that.
  If a PR is still open we can work on the same branch.
  If you don't know what upstream is ask!
- Be sure to run `cabal build` when you're done making a series of code changes, this can be intermediately run as well to ensure things are consistent. Do not finish the task until the typechecker passes.
- Repair all newly introduced warnings.
- If we're implementing any new function or behaviour, add a test to assert it works.
- At the end of a task and it typechecks, run `nix-build nix/ci.nix` to ensure CI passes, if that doesn't exist run `cabal test`.
- Commit your changes, message should contain the summary of the done work, the first line should be synopsis of that. At the end of the message include the prompt.
- Push the changes, don't force push.
- Open a pull request with the changes on github, you can target snoyberg/keter and winterland1989/mysql-haskell directly, otherwise make sure to target jappeace repository, or jappeace-sloth if jappeace don't exist.
- You're done once CI passes on github, if it doesn't trigger because it's out of sync, rebase then, you've to wait until it passes.
