from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from datetime import datetime, timezone


STATE_DIR = Path("/state")
STATE_DIR.mkdir(parents=True, exist_ok=True)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        target = self.path.lstrip("/") or "root"
        target = target.replace("/", "_")
        log_file = STATE_DIR / f"{target}.log"
        timestamp = datetime.now(timezone.utc).isoformat()
        with log_file.open("a", encoding="utf-8") as handle:
            handle.write(f"{timestamp} {self.path}\n")
        self.send_response(204)
        self.end_headers()

    def log_message(self, format, *args):
        return


HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
