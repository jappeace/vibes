{ pkgs }:
let
  pythonPackages = pkgs.python3Packages;

  # Decision: both servers and the libraries nixpkgs lacks (google-adk, the
  # two GA client libraries, mcp 1.x) are pinned PyPI wheels built with
  # buildPythonPackage; everything else comes from the nixpkgs pin. The
  # alternative was `uvx`/`pipx run` at launch, as the upstream READMEs
  # suggest. Rejected: an unpinned download on every start, and a fresh uvx
  # install of mcp-search-console broke when mcp 2.0 came out. The wheels are
  # pure python (py3-none-any), so there is no build system to reproduce.
  googleAnalyticsData = pythonPackages.buildPythonPackage {
    pname = "google-analytics-data";
    version = "0.23.3";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/c2/20/0afdbe14e02ff35967321774b9adc485cb9afed662f21010e29249f21fc0/google_analytics_data-0.23.3-py3-none-any.whl";
      hash = "sha256-dThQ+b0ilj4cepPmyFeUgPJUP6MSF4SJ012fxFO3Gd0=";
    };
    dependencies = [
      pythonPackages.google-api-core
      pythonPackages.google-auth
      pythonPackages.grpcio
      pythonPackages.proto-plus
      pythonPackages.protobuf
    ] ++ pythonPackages.google-api-core.optional-dependencies.grpc;
  };

  googleAnalyticsAdmin = pythonPackages.buildPythonPackage {
    pname = "google-analytics-admin";
    version = "0.30.2";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/58/bb/ee979e3bce5ba1e39fbf2363c07e17f330f79937aa11689080689931b019/google_analytics_admin-0.30.2-py3-none-any.whl";
      hash = "sha256-Qz4jdMq+J5aCGwumGJ4ntoYKcO9Y9ZGqJUTivmVUDjU=";
    };
    dependencies = [
      pythonPackages.google-api-core
      pythonPackages.google-auth
      pythonPackages.grpcio
      pythonPackages.proto-plus
      pythonPackages.protobuf
    ] ++ pythonPackages.google-api-core.optional-dependencies.grpc;
  };

  # analytics-mcp only uses ADK to turn its python functions into MCP tool
  # schemas, but it imports it unconditionally.
  googleAdk = pythonPackages.buildPythonPackage {
    pname = "google-adk";
    version = "2.14.1";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/53/47/fd40131a2ea09a2084e97253759d1325f1becab8185a6676961c7e48033a/google_adk-2.14.1-py3-none-any.whl";
      hash = "sha256-qSeD6ZurulYRFjzo+0ztPObF5jCjTxWjRgvFd1caQaM=";
    };
    # The pin has websockets 17; ADK caps it below 16 but the tool-schema
    # code analytics-mcp calls never touches websockets.
    pythonRelaxDeps = [ "websockets" ];
    dependencies = [
      pythonPackages.aiosqlite
      pythonPackages.authlib
      pythonPackages.click
      pythonPackages.cryptography
      pythonPackages.fastapi
      pythonPackages.google-auth
      pythonPackages.pyopenssl
      pythonPackages.google-genai
      pythonPackages.graphviz
      pythonPackages.httpx
      pythonPackages.jsonschema
      pythonPackages.opentelemetry-api
      pythonPackages.opentelemetry-sdk
      pythonPackages.packaging
      pythonPackages.pydantic
      pythonPackages.python-dotenv
      pythonPackages.python-multipart
      pythonPackages.pyyaml
      pythonPackages.requests
      pythonPackages.starlette
      pythonPackages.tenacity
      pythonPackages.typing-extensions
      pythonPackages.uvicorn
      pythonPackages.watchdog
      pythonPackages.websockets
    ];
  };

  analyticsMcp = pythonPackages.buildPythonApplication {
    pname = "analytics-mcp";
    version = "1.1.0";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/a0/1e/15f984496daf3a6f9c11ee02c7d1d96a9c63741c58791bc2853b87f10292/analytics_mcp-1.1.0-py3-none-any.whl";
      hash = "sha256-wZ5B3a5Aghi8KQRKrIYL8GUvIvFj5BpWiQL5Xq2Odxs=";
    };
    # Upstream pins google-auth ~=2.62, the nixpkgs pin has 2.57; the
    # service-account flow it uses predates both.
    pythonRelaxDeps = [ "google-auth" ];
    dependencies = [
      googleAnalyticsData
      googleAnalyticsAdmin
      googleAdk
      pythonPackages.google-auth
      pythonPackages.mcp
      pythonPackages.httpx
    ];
    pythonImportsCheck = [ "analytics_mcp.server" ];
  };

  # mcp-search-console is written against mcp 1.x (`mcp.server.fastmcp`),
  # which mcp 2 removed; the nixpkgs pin ships mcp 2.3.
  mcpVersion1 = pythonPackages.buildPythonPackage {
    pname = "mcp";
    version = "1.30.0";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/f5/f4/e58bc33317c92a0203664daaf00bf6f41166cc0149e5d6870a03f7cd004a/mcp-1.30.0-py3-none-any.whl";
      hash = "sha256-Zm7bUAlQPhBHydYDRqdW+UsmHwXMJiXyPUHHKP/EhNA=";
    };
    dependencies = [
      pythonPackages.anyio
      pythonPackages.httpx
      pythonPackages.httpx-sse
      pythonPackages.jsonschema
      pythonPackages.pydantic
      pythonPackages.pydantic-settings
      pythonPackages.pyjwt
      pythonPackages.cryptography
      pythonPackages.python-multipart
      pythonPackages.sse-starlette
      pythonPackages.starlette
      pythonPackages.typing-extensions
      pythonPackages.typing-inspection
      pythonPackages.uvicorn
      # the `cli` extra, which mcp-search-console requests
      pythonPackages.python-dotenv
      pythonPackages.typer
    ];
  };

  searchConsoleMcp = pythonPackages.buildPythonApplication {
    pname = "mcp-search-console";
    version = "0.4.2";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/73/87/c576be81c3b4f2e28126c8c504645fbf03e2f68ef7f2828b531f6d0c214d/mcp_search_console-0.4.2-py3-none-any.whl";
      hash = "sha256-+GraHwcbI6UpoihIPlfdCXgnNemYDwsqElttWSwY+8w=";
    };
    dependencies = [
      mcpVersion1
      pythonPackages.google-api-python-client
      pythonPackages.google-auth-httplib2
      pythonPackages.google-auth-oauthlib
      pythonPackages.platformdirs
    ];
    # gsc_server creates its config directory under $HOME on import.
    postInstall = "export HOME=$TMPDIR";
    pythonImportsCheck = [ "gsc_server" ];
  };
in
{
  inherit analyticsMcp searchConsoleMcp;

  # Only the two entry points go into the image: the applications' own
  # site-packages would otherwise be linked into the image's /lib next to the
  # system python.
  binaries = pkgs.runCommand "google-mcp-binaries" { } ''
    mkdir -p $out/bin
    ln -s ${analyticsMcp}/bin/analytics-mcp $out/bin/analytics-mcp
    ln -s ${searchConsoleMcp}/bin/mcp-search-console $out/bin/mcp-search-console
  '';
}
