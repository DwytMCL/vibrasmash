#!/bin/sh
cd "$(dirname "$0")" && if command -v python >/dev/null 2>&1; then exec python -m http.server 8080 --bind 127.0.0.1; else exec node serve.js 8080; fi
