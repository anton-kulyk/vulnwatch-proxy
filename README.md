# vulnwatch-proxy

Standalone 3proxy mini-project for VulnWatch: a small Docker Compose deployment
that starts an authenticating HTTP proxy with **one command** on any Unix VPS.

It exposes **two HTTP proxy ports**:

| Port | Authentication | Use | Clients |
|------|----------------|-----|---------|
| `3128` | **Basic auth** (login + password) | curl / Nuclei / WPScan / Guzzle | services that support proxy auth |
| `3129` | **None** (ACL-locked to source IP) | Chrome / Puppeteer | scanners that cannot send proxy basic-auth |

Both listeners exit through the VPS's own public IP. The exit country stays
consistent for every request through this proxy — useful for GeoIP-consistent
scanning without adding local network traffic.

## Deploy on a new server (step by step)

```bash
# 1. Packages (Ubuntu/Debian)
sudo apt update && sudo apt install -y docker.io docker-compose-plugin ufw

# 2. Firewall: allow SSH and the proxy ports.
#    3128 is public (basic-auth protects it); 3129 must be reachable by your
#    scanner VPS, so open it only from that IP/subnet, NOT from anywhere.
sudo ufw allow 22/tcp
sudo ufw allow 3128/tcp
sudo ufw allow from YOUR_SCANNER_VPS_IP to any port 3129 proto tcp   # e.g. 203.0.113.10
sudo ufw enable
sudo ufw status verbose

# 3. Clone and configure
git clone https://github.com/anton-kulyk/vulnwatch-proxy.git
cd vulnwatch-proxy
cp .env.example .env
nano .env
#    - set a strong PROXY_PASSWORD:  openssl rand -hex 24
#    - set PROXY_BROWSER_ALLOW_IP to YOUR_SCANNER_VPS_IP/32 (same IP as ufw above)

# 4. Start
docker compose up -d

# 5. Verify listening sockets (3129 must be *:3129, not 127.0.0.1:3129)
ss -tlnp | grep -E '3128|3129'

# 6. Local smoke test (from this server)
curl -s -x "http://USER:PASS@127.0.0.1:3128" http://ip-api.com/json
curl -s -x "http://127.0.0.1:3129"          http://ip-api.com/json
```

External verification — from your scanner VPS (not the proxy host):

```bash
# authenticated port - must return the proxy's exit IP
curl -s -x "http://USER:PASS@PROXY_PUBLIC_IP:3128" http://ip-api.com/json
# unauth browser port - must return the proxy's exit IP
curl -s -x "http://PROXY_PUBLIC_IP:3129" http://ip-api.com/json
```

If the browser port fails from outside but works locally, the two usual causes
are: (a) `ufw` doesn't allow `3129` from your VPS IP, or (b) the Docker port map
is still `127.0.0.1:3129:3129` (bind on the host). Check `docker compose ps` and
`ss -tlnp` first.

## Quick start (local only)

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

- The unauthenticated port `3129` is exposed publicly but is **ACL-locked** by
  `PROXY_BROWSER_ALLOW_IP` inside `entrypoint.lua`, and the Docker bind is a
  standard `3129:3129`, so the firewall rule (`ufw allow from <VPS> ... 3129`)
  is the second layer that keeps it closed to everyone else. Do not
  `ufw allow 3129/tcp` — use the `from <IP>` form.
- Secrets (login/password) live **only** in `.env` (gitignored); nothing is baked
  into the image or the repo.
- The image `ghcr.io/tarampampam/3proxy:2` is scratch-based and runs as a non-root
  user; the custom `entrypoint.lua` builds the two-listener config from env vars and
  `exec`s 3proxy, so the config never hard-codes credentials.

## Files

- `docker-compose.yml` — service definition, ports, healthcheck
- `entrypoint.lua` — generates `/etc/3proxy/3proxy.cfg` from env, then execs 3proxy
- `.env.example` — template for credentials and ports