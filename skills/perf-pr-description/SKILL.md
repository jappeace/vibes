---
name: perf-pr-description
description: "Write the description of a pull request whose point is a speed-up, especially one sent to someone else's repository (upstream contributions such as ekmett/thc). Use when opening or editing such a PR: it fixes the opening line, summary, measurement section, test plan and cc line Jappie approved, and requires the speed-up to be measured on the PR's own base first."
argument-hint: "[benchmark-url]"
---

# Performance PR descriptions

Jappie approved this shape on ekmett/thc#1152. Use it for any PR that
exists because of a measured speed-up. The `pr` skill still handles
pushing and creating the PR; this skill decides what the body says.

## First: measure on the PR's own base

The number in the opening line must come from the commit the PR targets
(its base, or its merge-base with the target branch) with only the PR's
commits on top.

ekmett/thc#1152 was closed over this. It claimed "26 to 30%", measured
on a fork branch that also carried two other patches. On upstream main
alone the same patch moved wall time by 0.4%, inside the noise: its gain
existed only once the other patches had removed a bigger bottleneck.

- Build the base and the PR head separately.
- Alternate cold runs (base, PR, base, PR) with an idle pause before
  each, at least three pairs. A laptop needs minutes, not seconds.
- Check every output against a reference, byte for byte where possible.
- Compare the difference of the means with the base's own spread. A
  difference smaller than that spread is not a claim.
- If the gain depends on other unmerged patches, send those first.

## Shape

1. An opening paragraph without heading: the measured effect, then the
   context sentence and link, in Jappie's words:
   "Reduces the wall time by 26 to 30%. For context I'm just trying to
   get the times down on this 1 billion row benchmark:
   https://github.com/jappeace/1br/tree/master/thc"
   Name the metric (wall time, CPU time, allocation) and give the range
   or the mean as measured. Never round up to a nicer number.
2. `## Summary`: two or three bullets. What cost time and how it was
   found (profile, trace, counter); what the change does; what stays the
   same (output, other modes, other platforms).
3. `## Measurement`: workload and flags, machine, base commit, before
   and after with the number of runs, range and mean, CPU time or
   allocation when they moved, and that the outputs matched.
4. `## Test plan`: checkboxes, ticked only for what ran, each with its
   result (suites or classes, modes, case counts). When a suite has known
   failures in this environment, run it on the unpatched base too and say
   the failing sets are identical. Say plainly what no test covers.
5. The attribution line, then `cc @jappeace` as the last line.

## Style

- First person, plain and short; the context sentence is Jappie's.
- No em-dashes inside sentences and no bold labels opening a bullet or
  paragraph.
- Every figure comes from a log you can point to.
- Follow the repository's rules on publishing numbers. THC's AGENTS.md
  keeps development benchmark results private unless the user requests
  publication; Jappie asking for the number in the PR is that request,
  and without it the numbers stay out.

## Process

1. Open the PR on the fork first (jappeace-sloth/<repo>, against a branch
   equal to upstream's target) so Jappie can read the diff and the text.
2. Open it upstream only after Jappie says so, with the same body.
3. If a later measurement contradicts the claim, correct the PR or close
   it with a comment giving the new numbers. Never leave a wrong number
   up.

## Template

```markdown
Reduces the <metric> by <measured range or mean>. For context I'm just trying to get the times down on <benchmark>: <link>

## Summary
- <what cost time, and how it was found>
- <what the change does, and what stays the same>

## Measurement
<workload and flags>, cold runs on <machine>, `<base sha>` (this PR's base): <before> before, <after> after (<n> alternating pairs, mean <m>); <CPU or allocation if it moved>. Every output identical to <reference>.

## Test plan
- [x] <classes or suite>, <modes>: <cases>, <result>
- [x] <full suite> on this branch and on unpatched `<base sha>`: <cases> each, the same <k> failing on both (<why they fail here>)
- <what no test observes>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

cc @jappeace
```

For the approved original and what its measurement got wrong, see
[example.md](example.md).
