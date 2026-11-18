"""Speaks just enough MCP over stdio to list a server's tools and call some.

Usage: mcp_client.py <server json> <calls json>
<server json> is one entry of the launcher's MCP server map
({"command", "args", "env"}); <calls json> is a list of
{"name", "arguments"}. Prints {"tools": [names], "calls": [results]}.
"""
import json
import os
import subprocess
import sys


def send(server, message):
    server.stdin.write(json.dumps({"jsonrpc": "2.0", **message}) + "\n")
    server.stdin.flush()


def request(server, request_id, method, params):
    send(server, {"id": request_id, "method": method, "params": params})
    for line in server.stdout:
        message = json.loads(line)
        if message.get("id") == request_id:
            if "error" in message:
                sys.exit(f"{method} failed: {message['error']}")
            return message["result"]
    sys.exit(f"server exited with {server.wait()} before answering {method}")


def main():
    entry = json.loads(sys.argv[1])
    calls = json.loads(sys.argv[2])
    server = subprocess.Popen(
        [entry["command"], *entry["args"]],
        env={**os.environ, **entry.get("env", {})},
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    )
    request(server, 0, "initialize", {
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "vibes-check", "version": "0"},
    })
    send(server, {"method": "notifications/initialized"})
    tools = request(server, 1, "tools/list", {})["tools"]
    results = []
    for request_id, call in enumerate(calls, start=2):
        results.append(request(server, request_id, "tools/call", call))
    server.stdin.close()
    server.wait(timeout=30)
    print(json.dumps({"tools": [tool["name"] for tool in tools], "calls": results}))


main()
