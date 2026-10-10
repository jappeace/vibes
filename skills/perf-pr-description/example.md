# ekmett/thc#1152: the approved description

Jappie approved this text. The shape is the one to copy. Its measurement
is the part not to copy: see the end.

````markdown
Reduces the wall time by 26 to 30%. For context I'm just trying to get the times down on this 1 billion row benchmark: https://github.com/jappeace/1br/tree/master/thc

## Summary
- `--run-executable` and `--run-io` loaded the entry with instrumentation on, but print the metrics only under `-Dthc.diagnostics=true`. Instrumentation only feeds those metrics, and their counters are `AtomicLong`s shared by every guest thread: with 1br's sixteen workers the tail-bounce counter, bumped on every loop iteration, was 3.8% of steady-state CPU samples in a billion-row run that never printed it, and the contended cache lines cost far more wall time than that.
- These launchers now instrument exactly when they will print the report, so their output is unchanged. The integer-entry mode keeps instrumenting, because it reads `compiledEntries` for its own checks.

## Measurement
A billion rows with `-Dpolyglot.compiler.MaximumGraalGraphSize=400000 -Dpolyglot.engine.OSR=false`, cold runs on a 16-thread Ryzen AI 7 350, THC `4c198dde` plus two other runtime patches from `jappeace-sloth/thc` branch `1br-performance-v2`: 117.5 s before, 82.5 to 92.4 s after (three runs, mean 87.0 s); CPU time 1483 s to 969 s. Every report byte-identical to native GHC's. Not yet measured on this base (`b736316a`).

## Test plan
- [x] `thc.NativeContextTest` and `thc.LauncherDiagnosticsTest` on this branch, `testDefault` and `testDense`: 17 cases each, no failures
- [x] the new test checks the diagnostics switch; `LauncherDiagnosticsTest` checks the launcher's output with diagnostics unset, `false` and `true`. No test observes the instrumentation itself.
- [x] THC's commit group (`fast_ci.py start`, `compile-common`, `group --group commit --cadence commit`) on this branch and on unpatched `b736316a`: 910 cases each, the same 16 failing on both (environmental in this container: `/tmp` paths resolving into the nix store, native file-descriptor counts, `libstdc++.so.6` loading)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

cc @jappeace
````

## What its measurement got wrong

The figures came from `4c198dde` plus two other patches, not from the
PR's base. Measured afterwards on the base itself (`b736316a`, three
alternating cold pairs, same flags), the billion-row run took 171.1 s
without the patch and 170.5 s with it: 0.4%, while the base alone varied
by 2.6 s. CPU time fell about 2%. The PR was closed with those numbers,
and the two patches it depended on were sent first.

Measured first, the measurement section would have read:

> A billion rows with `-Dpolyglot.compiler.MaximumGraalGraphSize=400000
> -Dpolyglot.engine.OSR=false`, cold runs on a 16-thread Ryzen AI 7 350,
> `b736316a` (this PR's base): 170.2, 172.8 and 170.4 s before, 167.5,
> 175.0 and 169.0 s after (three alternating pairs), CPU time 2332 s to
> 2277 s on average. Every report identical to native GHC's. The wall
> time difference is inside the run-to-run spread.

and the opening line would have claimed nothing about wall time.
