#!/usr/bin/env python3
"""
Easy Hindi Typing — Localhost Server
Part of Debian Dev Suite (100% Offline & Privacy-Focused)

Binds strictly to 127.0.0.1 (localhost) to ensure 0 external network exposure.
"""

import sys
import os
import socket
import argparse
import webbrowser
import threading
import time
from http.server import HTTPServer, SimpleHTTPRequestHandler

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

class LocalhostRequestHandler(SimpleHTTPRequestHandler):
    """Custom request handler that serves files from the app directory with UTF-8 and no-cache headers."""
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        # Prevent aggressive browser caching during local edits and ensure UTF-8
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        super().end_headers()

    def log_message(self, format, *args):
        # Keep terminal output clean
        sys.stderr.write(f"[EasyHindiTyping] {self.address_string()} - {format % args}\n")

def is_port_in_use(port, host=DEFAULT_HOST):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex((host, port)) == 0

def find_available_port(start_port=DEFAULT_PORT, host=DEFAULT_HOST, max_tries=20):
    port = start_port
    for _ in range(max_tries):
        if not is_port_in_use(port, host):
            return port
        port += 1
    return None

def open_browser_later(url, delay=0.6):
    def _open():
        time.sleep(delay)
        print(f"[EasyHindiTyping] Opening web browser: {url}")
        webbrowser.open(url)
    t = threading.Thread(target=_open, daemon=True)
    t.start()

def main():
    parser = argparse.ArgumentParser(description="Easy Hindi Typing Localhost Server")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Port to bind (default: 8765)")
    parser.add_argument("--host", default=DEFAULT_HOST, help="Host to bind (default: 127.0.0.1)")
    parser.add_argument("--no-browser", action="store_true", help="Do not automatically open the default browser")
    args = parser.parse_args()

    port = args.port
    if is_port_in_use(port, args.host):
        print(f"[EasyHindiTyping] Port {port} is already active on {args.host}.")
        url = f"http://{args.host}:{port}"
        if not args.no_browser:
            print(f"[EasyHindiTyping] Opening browser to existing instance: {url}")
            webbrowser.open(url)
        sys.exit(0)

    try:
        server = HTTPServer((args.host, port), LocalhostRequestHandler)
    except OSError as err:
        print(f"[EasyHindiTyping] Error binding to {args.host}:{port}: {err}")
        alt_port = find_available_port(port + 1, args.host)
        if alt_port:
            port = alt_port
            server = HTTPServer((args.host, port), LocalhostRequestHandler)
        else:
            sys.exit(1)

    url = f"http://{args.host}:{port}"
    print("=" * 60)
    print("  EASY HINDI TYPING — LOCALHOST APP")
    print(f"  URL: {url}")
    print(f"  Serving Directory: {DIRECTORY}")
    print("  Security: Bound strictly to 127.0.0.1 (Localhost Only)")
    print("  Privacy: 100% Offline • Zero Telemetry")
    print("=" * 60)
    print("Press Ctrl+C to stop the server.\n")

    if not args.no_browser:
        open_browser_later(url)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[EasyHindiTyping] Shutting down gracefully...")
    finally:
        server.server_close()
        print("[EasyHindiTyping] Server stopped.")

if __name__ == "__main__":
    main()
