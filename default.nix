{ uid, gid }:
let
  sources = import ./npins/default.nix;
  pkgs = import sources.nixpkgs { config.allowUnfree = true; };
  # passwd needs Nix interpolation for bashInteractive path, so use writeText
  systemPasswd = pkgs.writeText "passwd" ''
    root:x:0:0:System Tech Leadership:/root:/bin/sh
    claude:x:${toString uid}:${toString gid}:Claude:/home/claude:${pkgs.bashInteractive}/bin/bash
    nixbld1:x:30001:30000:Nix build user 1:/var/empty:/sbin/nologin
    nixbld2:x:30002:30000:Nix build user 2:/var/empty:/sbin/nologin
    nixbld3:x:30003:30000:Nix build user 3:/var/empty:/sbin/nologin
    nixbld4:x:30004:30000:Nix build user 4:/var/empty:/sbin/nologin
    nixbld5:x:30005:30000:Nix build user 5:/var/empty:/sbin/nologin
    nixbld6:x:30006:30000:Nix build user 6:/var/empty:/sbin/nologin
    nixbld7:x:30007:30000:Nix build user 7:/var/empty:/sbin/nologin
    nixbld8:x:30008:30000:Nix build user 8:/var/empty:/sbin/nologin
    nixbld9:x:30009:30000:Nix build user 9:/var/empty:/sbin/nologin
    nixbld10:x:30010:30000:Nix build user 10:/var/empty:/sbin/nologin
  '';

  playwrightBrowsers = pkgs.playwright-driver.browsers.override {
    withFirefox = false;
    withWebkit = false;
    withFfmpeg = false;
    withChromiumHeadlessShell = false;
  };

  playwrightMcp = pkgs.playwright-mcp.override {
    playwright-driver = pkgs.playwright-driver // {
      browsers = playwrightBrowsers;
    };
  };

  chromiumBin = pkgs.runCommand "chromium-bin" {} ''
    mkdir -p $out/usr/local/bin
    ln -s ${playwrightBrowsers}/chromium-*/chrome-linux64/chrome $out/usr/local/bin/chromium
  '';

  # Use our fork of mcp-server with protocol negotiation fix:
  # https://github.com/drshade/haskell-mcp-server/pull/11
  mcp-server-src = pkgs.fetchFromGitHub {
    owner = "jappeace-sloth";
    repo = "haskell-mcp-server";
    rev = "5b63c34";
    hash = "sha256-+55fUuWijK3cr1Jo43y/GtaE058HWsEjRt2jjE0hax4=";
  };

  mcpHoogle = let
    hpkgs = pkgs.haskellPackages.override {
      overrides = hnew: hold: {
        mcp-server = pkgs.haskell.lib.dontCheck
          (hnew.callCabal2nix "mcp-server" mcp-server-src { });
        mcp-hoogle = pkgs.haskell.lib.overrideCabal
          (hnew.callCabal2nix "mcp-hoogle" sources.mcp-hoogle { })
          (drv: {
            enableLibraryProfiling = false;
            enableExecutableProfiling = false;
            doHaddock = false;
            enableSharedExecutables = false;
            postFixup = "rm -rf $out/lib $out/nix-support $out/share/doc";
          });
      };
    };
  in hpkgs.mcp-hoogle;

  tmuxMcp = pkgs.rustPlatform.buildRustPackage {
    pname = "tmux-mcp-rs";
    version = "0.2.1";
    src = sources.tmux-mcp;
    cargoHash = "sha256-MZV/yuTMOdsOQqjdNflaIJSJzgQ3KXAo5xgnesmltoE=";
  };

  # The end-of-turn gate, compiled from ./gate. Replaces the old bash hook
  # trio (record-edit / reset-turn-state / stop-gate) with one binary exposing
  # `vibes-gate record|reset|stop-gate`. justStaticExecutables keeps only the
  # binary out of the image; dontCheck keeps the image build fast (the test
  # suite runs in the gate project's own CI, gate/nix/ci.nix).
  vibesGate = pkgs.haskell.lib.justStaticExecutables
    (pkgs.haskell.lib.dontCheck
      (pkgs.haskellPackages.callCabal2nix "vibes-gate" ./gate { }));

  entrypoint = pkgs.writeScript "entrypoint" (builtins.readFile ./entrypoint.sh);
  dockerEntrypoint = pkgs.writeScript "docker-entrypoint" (builtins.readFile ./docker-entrypoint.sh);

  # One shared Playwright MCP server per container, run as a sidecar by the
  # entrypoints. Both the main agent and the nested gate critics connect to it
  # over HTTP (see claude.sh MCP_CONFIG) instead of each cold-spawning its own
  # chromium, so the critic gets a warm browser for evidence-gathering. Bound to
  # loopback with the host check disabled (safe: not externally reachable). The
  # port 9223 is mirrored in claude.sh MCP_CONFIG and the entrypoint readiness
  # probe; keep the three in sync. Respawns if the server exits so it self-heals.
  playwrightSidecar = pkgs.writeShellScriptBin "playwright-mcp-sidecar" ''
    set -u
    while true; do
      ${playwrightMcp}/bin/playwright-mcp \
        --port 9223 --host 127.0.0.1 --allowed-hosts '*' \
        --headless --no-sandbox --isolated --ignore-https-errors \
        --executable-path /usr/local/bin/chromium
      echo "playwright-mcp-sidecar: server exited ($?), restarting in 2s" >&2
      sleep 2
    done
  '';

  env = pkgs.buildEnv {
    name = "image-root";
    paths = [
      pkgs.bashInteractive
      pkgs.coreutils
      pkgs.gh
      pkgs.npins
      pkgs.python3
      pkgs.git
      pkgs.curl
      pkgs.dnsutils # dig, nslookup, delv, nsupdate (DNS/hosting debugging)
      pkgs.bind.host # the `host` binary (not shipped in dnsutils)
      pkgs.xz
      pkgs.su-exec
      pkgs.lix # better nix
      pkgs.w3m
      pkgs.cacert
      pkgs.gnugrep
      pkgs.gnused
      pkgs.which
      pkgs.claude-code
      pkgs.cowsay
      pkgs.util-linux
      pkgs.jq
      pkgs.openssh
      pkgs.iana-etc
      playwrightMcp
      playwrightSidecar
      chromiumBin
      pkgs.tmux
      tmuxMcp
      mcpHoogle
      vibesGate
      (pkgs.writeTextDir "etc/image-manifest" ''
        mcp-hoogle-rev: ${builtins.substring 0 7 sources.mcp-hoogle.revision}
        mcp-server-rev: ${mcp-server-src.rev}
        tmux-mcp-rev: ${builtins.substring 0 7 sources.tmux-mcp.revision}
        built-epoch: ${toString builtins.currentTime}
      '')
      (pkgs.runCommand "setup-env" {} ''
    # Create necessary directories (added var/empty for nixbld users)

    mkdir -p $out/home/claude $out/tmp $out/var/empty
    mkdir -p $out/etc/nix
    # Pre-create bind-mount points so systemd-nspawn binds don't race.
    mkdir -p $out/home/claude/.claude $out/home/claude/.ssh
    mkdir -p $out/home/claude/vibes $out/home/claude/character
    touch $out/home/claude/.claude.json

    # Write config files directly into the rootfs rather than as symlinks to
    # nix store paths. Store symlinks created by writeTextDir break when nix
    # GC runs inside the container.
    cp ${./nix.conf} $out/etc/nix/nix.conf
    cp ${./builder-ssh-config} $out/etc/nix/builder-ssh-config
    cp ${systemPasswd} $out/etc/passwd

    cat > $out/etc/nsswitch.conf << 'NSSWITCH'
    passwd:    files
    group:     files
    shadow:    files
    NSSWITCH

    # systemd-nspawn refuses to boot a rootfs without an os-release file.
    cat > $out/etc/os-release << 'OSRELEASE'
    NAME="claude-env"
    ID=claude-env
    PRETTY_NAME="Claude Environment (Nix)"
    OSRELEASE

    cat > $out/etc/group << 'GROUP'
    root:x:0:
    claude:x:100:
    nixbld:x:30000:claude
    GROUP

    cat > $out/etc/gitconfig << 'GITCONFIG'
    [user]
      name = jappeace-sloth
      email = sloth@jappie.me
    GITCONFIG

    # Ownership of /home/claude is set at runtime in claude.sh after
    # cp -a from the store path into $RUNTIME_ROOT: the copy already
    # falls back to the caller's uid (cp -a preserves ownership only
    # when running as root), so build-time chown is redundant.
    #
    # It was also broken under the default NixOS sandbox: builders run
    # in a user namespace whose uid_map only contains the build user,
    # so chown to any other uid returns EINVAL.
    chmod 1777 $out/tmp

    # Provide /usr/bin/env so scripts using the conventional
    # `#!/usr/bin/env bash` shebang execute. The image otherwise
    # only ships /bin and /usr/local/bin, so env-shebanged scripts
    # die with "/usr/bin/env: bad interpreter".
    mkdir -p $out/usr/bin
    ln -s ${pkgs.coreutils}/bin/env $out/usr/bin/env
  '')
    ];
    pathsToLink = [ "/" ];
  };
in

{
  inherit env entrypoint;

  image = pkgs.dockerTools.buildImage {
    name = "claude-env";
    tag = "latest";

    copyToRoot = env;

    config = {
      Entrypoint = [ "${dockerEntrypoint}" ];
      Env = [
        "HOME=/home/claude"
        "USER=claude"
        "TERM=xterm-256color"
        "COLORTERM=truecolor"
        "NODE_OPTIONS=--dns-result-order=ipv4first"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        # docker-entrypoint.sh starts nix-daemon locally in the container
        "PATH=/bin:/nix/var/nix/profiles/default/bin"
        "NIX_PATH=nixpkgs=${pkgs.path}"
      ];
      WorkingDir = "/home/claude";
    };
  };
}
