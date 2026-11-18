"""A stand-in for Google's OAuth token endpoint that rejects every key the way
Google rejects a key it did not issue. Writes its port to argv[1]."""
import http.server
import json
import sys


class RejectingTokenEndpoint(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        body = json.dumps({"error": "invalid_grant", "error_description": "Invalid JWT Signature."}).encode()
        self.send_response(400)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


server = http.server.HTTPServer(("127.0.0.1", 0), RejectingTokenEndpoint)
with open(sys.argv[1], "w") as port_file:
    port_file.write(str(server.server_address[1]))
server.serve_forever()
