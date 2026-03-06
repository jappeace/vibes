{ pkgs ? import <nixpkgs> {} }:

pkgs.dockerTools.buildImage {
  name = "claude-env";
  tag = "latest";

  contents = [
    pkgs.bashInteractive
    pkgs.coreutils
    pkgs.nodejs_22
    pkgs.gh
    pkgs.git
    pkgs.curl
    pkgs.xz
    pkgs.nix
    pkgs.cacert
    pkgs.gnugrep
    pkgs.gnused
    pkgs.which
    pkgs.claude

  ];

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
