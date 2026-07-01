import http.server
import os
import sys

# Flutter's web build always names its output main.dart.js (no content hash),
# so browsers can silently keep serving a stale compiled bundle after a
# rebuild unless the server explicitly refuses to let anything be cached.
os.chdir(os.path.join(os.path.dirname(__file__), "..", "packages", "app", "build", "web"))

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        super().end_headers()

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8082
http.server.test(HandlerClass=Handler, port=port, bind="localhost")
