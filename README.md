# vulnwatch-proxy

Standalone 3proxy mini-project for VulnWatch: a small Docker Compose deployment
that starts an authenticating HTTP proxy with **one command** on any Unix VPS.

It exposes **two HTTP proxy ports**:

| Port | Authentication | Use | Clients |
|------|----------------|-----|---------|
| `3128` | **Basic auth** (login + password) | curl / Nuclei / WPScan / Guzzle | services that support proxy auth |
| `3129` | **None** (ACL-locked to source IP) | Chrome / Puppeteer | scanners that cannot send proxy basic-auth |

Both listeners exit through the VPS's own IP (this machine: `62.4.56.82`, Montenegro).
The exit country stays consistent for every request through this proxy — useful for
GeoIP-consistent scanning without adding local network traffic.

## Quick start

```bash
cp .env.example .env
# edit .env — set PROXY_LOGIN and a strong PROXY_PASSWORD (openssl rand -hex 24)
docker compose up -d
```

Smoke test:

```bash
# authenticated listener (3128)
curl -s -x "http://USER:PASS@127.0.0.1:3128" http://ip-api.com/json

# unauthenticated listener (3129) — only reachable from the allowed source
curl -s -x "http://127.0.0.1:3129" http://ip-api.com/json
```

## Security notes

- The unauthenticated port `3129` is bound to **host loopback** (`127.0.0.1:3129:3129`)
  in `docker-compose.yml` by default, so it is not exposed externally. In the proxy
  config it is additionally ACL-locked to `PROXY_BROWSER_ALLOW_IP`.
- Secrets (login/password) live **only** in `.env` (gitignored); nothing is baked
  into the image or the repo.
- The image `ghcr.io/tarampampam/3proxy:2` is scratch-based and runs as a non-root
  user; the custom `entrypoint.lua` builds the two-listener config from env vars and
  `exec`s 3proxy, so the config never hard-codes credentials.

## Files

- `docker-compose.yml` — service definition, ports, healthcheck
- `entrypoint.lua` — generates `/etc/3proxy/3proxy.cfg` from env, then execs 3proxy
- `.env.example` — template for credentials and ports
