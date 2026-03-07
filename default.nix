let
  sources = import ./npins/default.nix;
  pkgs = import sources.nixpkgs { config.allowUnfree = true; };
  systemGitConfig = pkgs.writeTextDir "etc/gitconfig" ''
    [user]
      name = jappeace-sloth
      email = sloth@jappie.me
  '';
in

pkgs.dockerTools.buildImage {
  name = "claude-env";
  tag = "latest";
  extraCommands = ''
    # Create the directory first
    mkdir -p home/claude
    # Note: Use relative paths (home/claude) or absolute (/home/claude)
    # but ensure the parent exists before chown
    chown -R 1000:100 home/claude
  '';

  copyToRoot = pkgs.buildEnv {
    name = "image-root";
    paths = [
      systemGitConfig
      pkgs.bashInteractive
      pkgs.coreutils
      pkgs.gh
      pkgs.python3
      pkgs.git
      pkgs.curl
      pkgs.xz
      pkgs.nix
      pkgs.w3m
      pkgs.cacert
      pkgs.gnugrep
      pkgs.gnused
      pkgs.which
      pkgs.claude-code
    ];
    pathsToLink = [ "/" ];
  };

  config = {
    Cmd = [ "/bin/bash" ];
    Env = [
      "PATH=/bin"
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "NIX_PAGER=cat"
    ];
    WorkingDir = "/projects";
  };
}
