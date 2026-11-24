"""API de simulation locale, données fictives et fautes déterministes."""
import json
import os
import re
import threading
import time
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

PAGES = 6
ATTEMPTS = OrderedDict()
LOCK = threading.Lock()
DELAY = float(os.environ.get("API_LATENCY_SECONDS", "0.12"))
if not 0 <= DELAY <= 2:
    raise ValueError("API_LATENCY_SECONDS doit être compris entre 0 et 2")


def offer(i):
    return dict(offer_id=f"O{i:03}", supplier_id=f"F{(i-1)%3+1:02}",
                product_id=i, price_cents=500 + 125*i, currency="EUR",
                available_units=2*i, observed_on="2026-11-24")


class Handler(BaseHTTPRequestHandler):
    def send(self, status, payload, headers=None):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        parts = urlsplit(self.path)
        if parts.path == "/health":
            return self.send(200, {"status": "ok"})
        params = parse_qs(parts.query)
        if parts.path == "/demo":
            time.sleep(DELAY)
            return self.send(200, {"unite": "litre", "valeur": 42})
        if parts.path != "/offers":
            return self.send(404, {"error": "route"})
        try:
            page = int(params.get("page", ["1"])[0])
        except ValueError:
            return self.send(400, {"error": "page"})
        scenario = params.get("scenario", ["atelier"])[0]
        run = params.get("run", ["demo"])[0]
        if not 1 <= page <= PAGES or scenario not in {"clean", "atelier", "panne"} or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", run):
            return self.send(400, {"error": "parametres"})
        key = (scenario, run, page)
        with LOCK:
            attempt = ATTEMPTS.get(key, 0) + 1
            ATTEMPTS[key] = attempt
            ATTEMPTS.move_to_end(key)
            if len(ATTEMPTS) > 512:
                ATTEMPTS.popitem(last=False)
        time.sleep(DELAY)
        if scenario == "panne" and page == 6:
            return self.send(503, {"error": "indisponible"})
        if scenario == "atelier" and attempt == 1:
            if page == 2:
                return self.send(429, {"error": "limite temporaire"}, {"Retry-After": "1"})
            if page == 3:
                return self.send(200, b"{json-incomplet")
            if page == 4:
                time.sleep(1.4)
        rows = [offer(i) for i in range((page-1)*4+1, page*4+1)]
        if scenario == "atelier":
            if page == 2:
                del rows[0]["supplier_id"]
            if page == 3:
                rows[1]["price_cents"] = "inconnu"
            if page == 5:
                rows[0]["product_id"] = 9999
            if page == 6:
                rows[-1] = offer(1)
        self.send(200, {"page": page, "total_pages": PAGES,
                        "next_page": page+1 if page < PAGES else None, "items": rows})


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
