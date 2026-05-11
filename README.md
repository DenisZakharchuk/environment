# Self-Hosted Infrastructure Stack

A modular, self-hosted infrastructure stack for a single Linux server (tested on Raspberry Pi CM5, arm64). Each service group is an independent scope — deploy only what you need, start and stop scopes individually, reset a single scope without touching the others.

## Architecture

```
environment/
├── core/           # Traefik, Step CA (internal CA), Technitium DNS, Docker API proxy
├── identity/       # Authentik (SSO/OIDC) + PostgreSQL + Redis
├── vpn/            # WireGuard Easy
├── git/            # Forgejo (Git) + Woodpecker CI
├── files/          # SFTPGo (file sharing, SFTP, WebDAV)
├── mail/           # Stalwart Mail (SMTP/IMAP/JMAP)
├── calendar/       # Radicale (CalDAV/CardDAV)
├── messenger/      # Matrix Dendrite + Element Web
├── monitoring/     # Prometheus + Loki + Promtail + Grafana
├── scopes/         # Scope metadata — single source of truth per scope
├── scripts/        # Bootstrap and lifecycle scripts
├── data/           # Runtime bind-mount data (gitignored)
├── .env.example    # All configuration variables with descriptions
└── Makefile        # All lifecycle commands
```

All containers share the `infra_net` Docker bridge network. Traefik auto-discovers routes via Docker labels and requests TLS certificates from the internal Step CA over ACME — no manual certificate management.

### Service URLs (replace `infra.home` with your domain)

| Scope | Service | URL |
|---|---|---|
| network | Traefik dashboard | `https://traefik.infra.home` |
| network | Certificate Authority | `https://ca.infra.home` |
| network | DNS admin | `https://dns.infra.home` |
| network | VPN management | `https://vpn.infra.home` |
| identity | SSO / Identity | `https://auth.infra.home` |
| dev | Git hosting | `https://git.infra.home` |
| dev | CI/CD | `https://ci.infra.home` |
| productivity | File sharing | `https://files.infra.home` |
| productivity | Mail admin | `https://mail.infra.home` |
| productivity | Calendar / Contacts | `https://cal.infra.home` |
| communication | Chat (Element) | `https://chat.infra.home` |
| communication | Matrix homeserver | `https://matrix.infra.home` |
| observability | Grafana | `https://grafana.infra.home` |
| observability | Prometheus | `https://prometheus.infra.home` |

## Prerequisites

- Docker Engine 25+ with the Compose plugin (`docker compose`)
- Ports 80, 443, 53/udp, 53/tcp available on the host
- `make`, `openssl`, `htpasswd` (`apache2-utils`) installed

### Installing prerequisites (Debian / Ubuntu / Raspberry Pi OS)

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y make curl git openssl apache2-utils

# Docker Engine (official repo)
sudo apt install -y ca-certificates gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER && newgrp docker
```

> **Ubuntu**: replace `/linux/debian` with `/linux/ubuntu` in the repo URL.  
> **Raspberry Pi OS**: use the `debian` URL — it is Debian-based.

## Quick Start

### 1. Clone and run the setup wizard

```bash
git clone https://github.com/DenisZakharchuk/environment.git
cd environment
make setup
```

The wizard:
1. Presents an interactive scope selection menu (choose which service groups to deploy)
2. Prompts for your internal domain, server LAN IP, and all passwords (12+ chars, confirmed twice)
3. Auto-generates cryptographic secrets (`AUTHENTIK_SECRET_KEY`, `WOODPECKER_AGENT_SECRET`, WireGuard bcrypt hash, Traefik htpasswd)
4. Writes a complete `.env`
5. Calls `make init` automatically, which: creates the `infra_net` Docker network, creates all data directories, initialises Step CA and writes its root cert fingerprint back into `.env`, generates the Dendrite signing key

If `.env` already exists, the wizard offers to re-run, skip to init only, or quit.

### 2. Configure DNS

Start the network scope:

```bash
make network-up
```

Open `http://HOST_IP:5380` (Technitium DNS admin — direct IP, no VPN needed yet) and:
- **Zones → Add Zone**: type your domain (e.g. `infra.home`), type: Primary
- **Add Record**: type `A`, name `*.infra.home`, value `HOST_IP` (wildcard)
- **Settings → Forwarders**: add `1.1.1.1` and `8.8.8.8`

### 3. Connect to VPN

All internal services (`https://*.infra.home`) are only reachable through the WireGuard VPN. Connect once and everything is available — no per-device DNS changes needed, physical network untouched.

**Create a peer** (from any machine that can reach `HOST_IP` directly):

1. Open `http://HOST_IP:51821` (wg-easy UI — direct IP, before VPN is connected)
2. Log in with the WireGuard password set during `make setup`
3. Click **+ New Client**, name it, download or scan the QR code
4. Connect with the WireGuard client on your device

The generated client config includes:
- `DNS = HOST_IP` — all DNS queries go to Technitium through the tunnel; `*.infra.home` resolves, public domains forward upstream
- `AllowedIPs = 10.8.0.0/24, 192.168.50.0/24` — split tunnel: only VPN and server subnet traffic routes through the Pi, internet goes direct

> **Adjusting `WG_ALLOWED_IPS`**: edit `.env` and recreate peers in the wg-easy UI (the value is baked into client configs at peer creation time). Use `0.0.0.0/0` for full tunnel.

Once connected, `https://*.infra.home` works in the browser from any VPN-connected device.

### 4. Start identity (SSO)

```bash
make identity-up
```

Open `https://auth.infra.home`, complete the Authentik first-run wizard, and set the `akadmin` password.

### 5. Start remaining scopes

```bash
make dev-up
make productivity-up
make communication-up
make observability-up
```

Or start everything listed in `ENABLED_SCOPES` (.env) at once:

```bash
make up
```

### 6. Configure OIDC integrations

After services are up, create OIDC apps in Authentik (and the Forgejo OAuth app for Woodpecker), then run:

```bash
make configure-oidc
```

This interactive script walks through each integration, shows you where to find each token, and writes the values into `.env`. Restart affected services afterwards.

## Scopes

Services are grouped into **scopes** — logical deployment units with declared dependencies. All metadata for a scope (compose dirs, data dirs, dependencies, health check) lives in a single file in `scopes/`. The scripts and Makefile read from these files — they are the single source of truth.

### Available scopes

| Scope | Services | Hard deps | Soft deps |
|---|---|---|---|
| `network` | Traefik, Step CA, Technitium DNS, WireGuard | — | — |
| `identity` | Authentik (SSO/OIDC) | network | — |
| `dev` | Forgejo, Woodpecker CI | network | identity |
| `productivity` | SFTPGo, Stalwart Mail, Radicale | network | identity |
| `communication` | Dendrite, Element Web | network | identity |
| `observability` | Prometheus, Loki, Grafana | network | identity |

**Hard dependency**: the scope refuses to start if the required scope's health check fails.  
**Soft dependency**: a warning is printed but startup proceeds (reduced functionality — no OIDC login).  
**Special case**: Radicale (calendar) uses Authentik forward-auth. `setup.sh` automatically enables `identity` when `productivity` is selected.

### Dependency graph

```
network  ←  always first
  └── identity  ←  SSO for all other scopes
        ├── (soft) dev
        ├── (soft) productivity
        ├── (soft) communication
        └── (soft) observability
```

### Makefile target naming — noun-verb convention

Targets are named `<scope>-<action>` so related commands are grouped together:

```
make network-up        make network-down        make network-purge
make identity-up       make identity-down       make identity-purge
make dev-up            make dev-down            make dev-purge
make productivity-up   make productivity-down   make productivity-purge
make communication-up  make communication-down  make communication-purge
make observability-up  make observability-down  make observability-purge
```

Aggregates:

```
make up           Start all ENABLED_SCOPES in dependency order
make down         Stop all scopes in reverse order
make purge        Purge all scopes (keeps .env)
make purge-full   Full factory reset — also deletes .env and .htpasswd
```

## Purging / Resetting

Each scope's `purge` action: stops its containers, removes its Docker named volumes, and deletes its `data/` subdirectories. Requires typed `yes` confirmation.

```bash
# Reset just the identity scope (Authentik + its DB)
make identity-purge

# Reset everything except .env (re-run make init + make up to restore)
make purge

# Full factory reset — blank slate, same as a fresh clone
make purge-full
```

Purge respects dependency order (network is purged last) and warns if a dependent scope is still running.

After purging, re-bootstrap with:

```bash
make init    # recreates data dirs, re-inits Step CA if needed
make up      # starts all ENABLED_SCOPES
```

## Adding a New Scope or Service

### Adding a service to an existing scope

1. Add the service to the scope's existing `docker-compose.yml`
2. Attach it to `infra_net`
3. Add Traefik labels: `traefik.enable=true`, routing rule, `tls=true`, `tls.certresolver=step-ca`
4. Add a DNS record in Technitium (or use the wildcard if the subdomain fits)

No other files need to change.

### Adding a new scope

1. Create `<name>/docker-compose.yml`
2. Create `scopes/<name>.sh` — define `SCOPE_COMPOSE_DIRS`, `SCOPE_DATA_DIRS`, `SCOPE_DEPENDS_ON`, `SCOPE_HEALTH_CHECK` (see any existing scope file as a template)
3. Add 3 lines to the Makefile:
   ```makefile
   <name>-up:    ## Description
   	@bash scripts/scope.sh <name> up
   <name>-down:  ## Description
   	@bash scripts/scope.sh <name> down
   <name>-purge: ## Description
   	@bash scripts/scope.sh <name> purge
   ```
4. Add the scope to `ALL_SCOPES_ORDERED` in `scripts/scope.sh`
5. Add scope prompts to `scripts/setup.sh`

Everything else (data dir creation, dependency checking, purge, health status) is driven automatically from the scope file.

## TLS / Certificate Architecture

- **Step CA** is the internal certificate authority, running as a container
- **ACME** is used by Traefik to request certificates per-hostname — no manual cert management
- **httpChallenge** is used: Step CA makes an HTTP request to port 80 on each domain to verify ownership; Traefik handles the challenge response
- Each router must have `tls.certresolver=step-ca` in its Docker labels for ACME to trigger
- Certificates are 90-day (Step CA default for ACME), renewed automatically
- The Step CA root certificate must be trusted by clients (browsers) — add it as a trusted CA once

## DNS and VPN Access

All internal services are accessed through the WireGuard VPN — this means:
- No per-device DNS configuration needed (VPN pushes `HOST_IP` as DNS automatically via `WG_DEFAULT_DNS`)
- Physical network connection and DNS are untouched when VPN is disconnected
- When VPN is off, `*.infra.home` is unreachable and the device uses its normal DNS

**DNS requirements:**
- Use an internal domain ending in `.home` or `.internal` (avoid `.local` — conflicts with mDNS)
- Wildcard A-record `*.yourdomain.home → HOST_IP` in Technitium
- Upstream forwarders (`1.1.1.1`, `8.8.8.8`) in Technitium so public domains resolve through the tunnel

**Split tunnel vs full tunnel (`WG_ALLOWED_IPS` in `.env`):**

| Value | Behaviour |
|---|---|
| `10.8.0.0/24,192.168.50.0/24` | Split tunnel — internet direct, internal traffic via VPN |
| `0.0.0.0/0` | Full tunnel — all traffic (including internet) through Pi |

After changing `WG_ALLOWED_IPS`, recreate all peers in the wg-easy UI — the value is baked into client configs at creation time.

## Post-Install Checklist

- [ ] `make setup` completed — `.env` has no placeholder values
- [ ] `make network-up` — Traefik, Step CA, Technitium DNS, WireGuard running
- [ ] Technitium: internal zone and wildcard A-record created, upstream forwarders set
- [ ] WireGuard peer created in wg-easy UI and connected — `https://*.infra.home` resolves in browser
- [ ] Step CA root certificate trusted in browser/OS (for green lock on internal sites)
- [ ] Authentik: first-run wizard completed, `akadmin` password set
- [ ] `make configure-oidc` run — all OIDC tokens written to `.env`
- [ ] Services restarted after `configure-oidc`
- [ ] Mail: SPF, DKIM, DMARC records in public DNS (if sending external mail)

## Makefile Reference

```
make help              Show all targets with descriptions
make setup             Interactive wizard: scope selection, passwords, secrets, writes .env + init
make init              Non-interactive bootstrap (requires .env)
make configure-oidc    Fill in post-UI OIDC tokens interactively
make status            Live health check for all ENABLED_SCOPES
make ps                Show running containers
make logs SVC=<dir>    Tail logs for a compose dir (e.g. SVC=core)
```

## Security Notes

- All traffic is TLS-encrypted via Traefik + internal Step CA
- HTTP → HTTPS redirect enforced globally by Traefik
- Security headers (HSTS, CSP, X-Frame-Options, etc.) applied globally via Traefik middleware
- `.env` is gitignored — never commit it; contains all secrets
- `data/` is gitignored — contains all persistent service state
- Authentik forward-auth protects internal services (Radicale, Prometheus, Grafana) from unauthenticated access

## Future: Router-level WireGuard Client (zero-config LAN DNS)

**Goal**: Instead of each home LAN device needing its own WireGuard peer, the router connects to the Pi's WireGuard server once (as a WireGuard client) and advertises `HOST_IP` as DNS via DHCP. Every device on the LAN gets `*.infra.home` resolution automatically — no WireGuard client installation needed per device.

Most consumer and prosumer routers support running as a WireGuard client: ASUS calls it "VPN Fusion", TP-Link calls it "VPN Client", Ubiquiti/UniFi, pfSense, OPNsense, MikroTik, and GL.iNet all expose it as a native WireGuard peer interface. The underlying mechanism is the same regardless of branding.

**Architecture:**
```
Router (WireGuard client peer) → Pi WireGuard server → Technitium DNS
    └── DHCP DNS = HOST_IP → all LAN devices resolve *.infra.home
Per-device WireGuard peers: still used for remote/mobile access outside home
```

**Planned steps:**
1. Create a dedicated peer in wg-easy named `router` — split tunnel `AllowedIPs: 10.8.0.0/24, 192.168.50.0/24`
2. In the router admin UI: add a WireGuard VPN client profile, paste the peer config from wg-easy
3. In the router admin UI: DHCP → DNS Server → `HOST_IP`, secondary `1.1.1.1`
4. Per-device VPN peers remain for mobile/remote access only

**Grey areas still to research:**
- Some router UIs ask for a Private Key directly — need to confirm whether the router generates its own keypair (and provides the public key to register in wg-easy) or expects a keypair generated externally via `wg genkey`
- Whether the router's VPN client UI allows specifying `AllowedIPs` per profile or forces a fixed value
- Interaction between the router's WireGuard DNS setting and any existing DNS-over-TLS or DNSSEC configuration on the router

## Future: Docker Swarm

The stack is intentionally single-node. Swarm migration is possible with minimal changes:

| Now (Compose) | Swarm |
|---|---|
| bridge network `infra_net` | overlay network |
| `docker compose up -d` | `docker stack deploy` |
| `.env` file | Docker Secrets |
| Traefik Docker provider | Traefik Docker Swarm provider (`swarmMode: true`) |
| labels on containers | `deploy.labels` in compose |
- **Storage**: replace bind mounts with named volumes or a distributed storage driver (NFS, GlusterFS, etc.)

This is reserved for a future iteration. The current single-node setup handles typical small-team workloads and is straightforward to migrate when horizontal scaling becomes necessary.
