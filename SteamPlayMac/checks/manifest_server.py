import http.server
import subprocess
import sys
import threading
import time


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/slow":
            time.sleep(1)
        status = 503 if self.path == "/error" else 200
        body = b"-1" if self.path == "/negative" else b"123456\n"
        self.send_response(status)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            pass

    def log_message(self, *_):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
server.daemon_threads = True
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    for path, expected in [("ok", "ok"), ("error", "fail"), ("negative", "fail"), ("slow", "fail")]:
        start = time.monotonic()
        subprocess.run([sys.argv[1], f"http://127.0.0.1:{server.server_port}/{path}", expected], check=True, timeout=3)
        if path == "slow":
            assert time.monotonic() - start < 0.9
finally:
    server.shutdown()
    server.server_close()
print("Steam-first manifest requests, response validation and timeout passed")
