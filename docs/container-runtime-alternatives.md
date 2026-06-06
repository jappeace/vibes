# Container-runtime alternatives for vibes

## Why look

Two pain points with the current Docker setup:

1. **Slow entry.** `docker load -i $(nix-build … -A image)` takes 1–2 minutes
   per launch even when nothing has changed. The Nix-built closure is round-tripped
   through a tarball and re-imported into Docker's layer store, on a host that already
   has every byte sitting in `/nix/store`.
2. **No nesting.** Docker's default seccomp profile blocks `clone(CLONE_NEWUSER)`,
   so from inside the container we cannot spin up a second container to test image
   changes. Already documented in `testing-mcp-from-container.md`.

Both stem from the same root: wrapping a Nix-built env in Docker's tarball/layer
format on a host that already has the Nix store.

## Options considered

| Option                              | Startup vs Docker | Nesting from inside | Complexity | Verdict                                                                 |
|-------------------------------------|-------------------|---------------------|------------|-------------------------------------------------------------------------|
| **systemd-nspawn** + `/nix` bind    | ~instant (no tarball) | Yes (userns works) | Low — single command | **Recommended.** Hits both gripes. Requires root or a sudo rule.       |
| **bubblewrap**                       | ~instant          | Yes                 | Medium — wire `/etc`, `/proc`, `/dev` yourself | Most lightweight. Closer to a fancy chroot than a container.            |
| **incus / LXC**                      | Fast after first launch | Yes (`security.nesting=true`) | Medium — profiles, lxc.conf | Overweight for "run claude, exit." Built for long-lived system containers. |
| **podman rootless**                  | Same as Docker (tarball still loaded) | Yes (rootless gives userns) | Low — drop-in `docker` alias | Fixes nesting only. Does not fix the slow load.                         |
| **nix2container** (keep Docker)      | Big improvement on load | No change           | Low        | Fixes load time, not nesting. Useful if migrating runtime is off the table. |

### systemd-nspawn — recommended

`nix-build -A env` produces a directory of symlinks into `/nix/store`. `nspawn`
boots straight off that directory:

```sh
nix-build ./default.nix -A env --arg uid $(id -u) --arg gid $(id -g)
sudo systemd-nspawn \
  --directory=result \
  --bind-ro=/nix \
  --bind="$(pwd)/instances/$INSTANCE_NAME":/home/claude/.claude \
  --bind="$(pwd)/../vibes/$INSTANCE_NAME":/home/claude/vibes \
  --setenv=INSTANCE_NAME=$INSTANCE_NAME \
  --user=claude \
  --ephemeral \
  claude
```

No tarball, no `docker load`. The host's `/nix/store` *is* the container's store.

### bubblewrap

`bwrap` is what flatpak uses. Faster and lighter than nspawn, but you build the
filesystem layout by hand — every `--ro-bind /etc/X /etc/X`, `--proc /proc`,
`--dev-bind /dev /dev` is your problem. Reasonable fallback if you can't get a
sudo rule for nspawn.

### incus / LXC

Modern LXC, daemon-based, lifecycle around long-lived containers with profiles
and snapshots. Wrong granularity for our "build env, drop into shell, exit"
workflow — most of the work would be fighting incus' lifecycle assumptions.

### podman rootless

Drop-in for `docker run`. Rootless mode gives userns by default → nesting works.
But it still consumes a Docker-format image, so the tarball/load step stays.
Fixes one gripe, not the other.

### nix2container

Third-party tool that builds Docker images with content-addressed layers per
Nix store path, so `docker load` only ingests changed paths. Plug-in replacement
for `dockerTools.buildImage`. Closes most of the load-time gap without
changing the runtime, but doesn't help with nesting.

## Answers to the specific questions

### Can systemd-nspawn run as a user?

Not really — `systemd-nspawn` needs `CAP_SYS_ADMIN` to set up mount, PID, and
network namespaces and to mount the API filesystems. There is no supported
rootless mode. `machinectl shell` only attaches to a *running* container, it
doesn't help with launch.

The pragmatic answer is a NOPASSWD sudoers rule scoped to nspawn:

```
jappie ALL=(root) NOPASSWD: /run/current-system/sw/bin/systemd-nspawn
```

If true rootless start is non-negotiable, only **bubblewrap** and **podman
rootless** in this list can do it. Both have downsides for vibes (bwrap = manual
filesystem wiring; podman = doesn't fix slow load).

### How secure is systemd-nspawn vs Docker?

Roughly comparable for our threat model (a misbehaving LLM, not a kernel-CVE
attacker). Both share the host kernel — neither is a VM. Differences:

| Layer            | Docker (default)                              | nspawn (default)                         |
|------------------|-----------------------------------------------|------------------------------------------|
| Seccomp          | Aggressive curated profile (~50+ syscalls blocked) | Smaller built-in filter — blocks mount, kernel-module load, ptrace across boundary |
| LSM (AppArmor/SELinux) | `docker-default` profile applied            | None by default; `--profile=` for templates |
| Capabilities     | Drops most, keeps a known set                 | Drops most, similar set                   |
| User namespaces  | Off by default (changing); root-in-container = uid 0 on host (mitigated by caps) | On with `-U` / `--private-users=pick` — uid 0 inside is a high uid outside |
| Network          | Bridge by default                             | Host by default; `--network-veth` for isolation |
| cgroups          | Yes                                           | Yes                                       |

**Docker's edge:** the seccomp + AppArmor profiles are battle-tested by years of
adversarial use. nspawn relies on systemd's correctness rather than a
purpose-built hardening profile.

**nspawn's edge:** `-U` enables user namespaces by default — root inside the
container maps to an unprivileged high uid outside. With Docker we still run
inside Docker's default profile but as a non-root user via su-exec, which is
weaker on paper.

For a sandbox against an LLM that might rm-rf the home directory or try to
write `/etc/shadow`, **nspawn is enough.** For a sandbox against a targeted
kernel-CVE attacker, neither is.

### Are host folders still hidden?

Yes, with the same discipline as Docker:

- `--directory=PATH` makes that the rootfs. Anything outside it is invisible.
- Host paths only appear via explicit `--bind` / `--bind-ro`.
- `/proc`, `/sys`, `/dev` are auto-mounted in a masked, read-only-where-it-matters
  form (same as Docker).

One real exposure to be aware of: `--bind-ro=/nix` mounts the **entire host Nix
store** read-only into the container. That's how we get the fast launch. Net
effect: the agent can `ls /nix/store` and see every derivation the host has ever
built. Not normally a leak (store paths are world-readable on disk), but worth
flagging — if you store secrets in Nix derivations, they're visible.

Mitigations if that matters:
- Bind only the closure of the env: `nix-store -qR result | xargs -I{} echo --bind-ro={}`
- Copy the closure to a per-instance store at launch (slower, breaks the speedup).

### Does claude still run as a user?

Yes, three layers:

- `--user=claude` — runs the entrypoint command as `claude` inside the container.
- The `/etc/passwd` we bake into `env` already defines `claude`, so it resolves.
- With `-U`, the container's `claude:1000` is some high uid like `525288` on the
  host. Better isolation than today's `su-exec` to the host's uid.

The current `entrypoint.sh` chown/su-exec dance can be deleted — `--user` and
`-U` handle it cleanly.

### Can I specify a full NixOS env for the nspawned container?

Yes. Two levels:

**(1) Just an env (what we do today)** — `buildEnv` of packages, plus a few
config files in `/etc`. Fastest. nspawn runs `claude` as PID 1 (or via
`--as-pid2` if you want a shim). No systemd inside.

**(2) Full NixOS toplevel** — build a NixOS system closure and `--boot` it as a
real machine. nspawn becomes PID 1 = systemd, full unit system, journald, the
works.

```nix
let
  system = (import "${pkgs.path}/nixos" {
    configuration = { config, pkgs, lib, ... }: {
      boot.isContainer = true;
      networking.hostName = "claude";
      users.users.claude = {
        isNormalUser = true;
        uid = 1000;
      };
      environment.systemPackages = with pkgs; [
        claude-code lix git curl tmux # …existing list
      ];
      systemd.services.nix-daemon.enable = true;
    };
  }).config.system.build.toplevel;
in {
  inherit system;
}
```

```sh
sudo systemd-nspawn --boot --directory=result/init/..  …
```

NixOS also ships a `nixos-container` CLI that wraps this pattern — uses nspawn
under the hood, adds machinectl integration.

Tradeoff: option (2) gives you proper service supervision and a "real" machine,
at the cost of ~1–2s extra boot to bring systemd up. For vibes' "start claude,
exit on EOF" loop, option (1) is the better fit; option (2) is there if you
later want long-running per-instance services.

## Migration sketch

If we go ahead with nspawn:

1. `default.nix` — keep `env`, drop the `dockerTools.buildImage` block (or guard
   it behind a flag so Docker remains as a fallback).
2. `claude.sh` — replace the `docker load` + `docker run` block with the nspawn
   invocation above. macOS branch can stay on Docker (no nspawn on Darwin).
3. `entrypoint.sh` — most of it is no longer needed. nix-daemon runs on the
   host; `--user=claude` removes the chown/su-exec dance. Keep the
   `/root/.ssh/builder_key` copy if remote builds are still in use, or move it
   into the nspawn bind list.
4. One-line sudoers rule for `systemd-nspawn`.
5. Side-by-side test: `./stan.sh` vs `./stan-nspawn.sh` for a week.

Expected wins, in priority order:

- 1–2 min → near-instant launch (the order-of-magnitude improvement).
- Nesting works → can rebuild and test images from inside a vibes instance.
- Less `entrypoint.sh` to maintain.
- Better uid isolation via `-U` than today's su-exec to host uid.
