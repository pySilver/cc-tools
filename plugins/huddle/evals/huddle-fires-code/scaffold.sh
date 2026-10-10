#!/usr/bin/env bash
# The workspace holds one file whose retry loop the user is asked about.
set -euo pipefail
cat > retry.py <<'PY'
import time


def upload_with_retry(client, payload, attempts=8):
    """Upload payload, retrying on connection errors."""
    last = None
    for _ in range(attempts):
        try:
            return client.upload(payload)
        except ConnectionError as e:
            last = e
            time.sleep(1)
    raise last


def upload(client, payload):
    return upload_with_retry(client, payload)
PY
