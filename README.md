# Lightweight Enterprise Infrastructure

A modular, self-hosted infrastructure stack built with Docker Compose. Each service group is independent — add or remove services without touching anything else.

## Architecture

```
environment/
├── core/           # Traefik (reverse proxy), Step CA (internal CA), Technitium DNS
├── identity/       # Authentik (SSO/OIDC) + PostgreSQL + Redis
├── vpn/            # WireGuard Easy (VPN + web UI)
├── git/            # Forgejo (Git hosting) + Woodpecker CI
├── files/          # SFTPGo (file sharing, SFTP, WebDAV, web UI)
├── mail/           # Stalwart Mail (SMTP/IMAP/JMAP)
├── calendar/       # Radicale (CalDAV/CardDAV)
├── messenger/      # Matrix Dendrite + Element Web
├── monitoring/     # Prometheus + Grafana + Loki + Promtail
├── scripts/        # Bootstrap scripts
├── data/           # Runtime data (gitignored)
├── .env.example    # All configuration variables
└── Makefile        # Orchestration commands
```

All containers share a single external Docker network (`infra_net`). Traefik auto-discovers services via Docker labels. Every service gets a TLS certificate from the internal Step CA via ACME — no manual cert management.

### Service URLs (replace `infra.local` with your domain)

| Service | URL |
|---|---|
| Traefik dashboard | `https://traefik.infra.local` |
| Certificate Authority | `https://ca.infra.local` |
| DNS admin | `https://dns.infra.local` |
| SSO / Identity | `https://auth.infra.local` |
| VPN management | `https://vpn.infra.local` |
| Git hosting | `https://git.infra.local` |
| CI/CD | `https://ci.infra.local` |
| File sharing | `https://files.infra.local` |
| Mail admin | `https://mail.infra.local` |
| Calendar / Contacts | `https://cal.infra.local` |
| Chat (Element) | `https://chat.infra.local` |
| Matrix homeserver | `https://matrix.infra.local` |
| Grafana | `https://grafana.infra.local` |
| Prometheus | `https://prometheus.infra.local` |

## Prerequisites

- Docker Engine 25+ with the Compose plugin (`docker compose`)
- Ports 80, 443, 53 available on the host
- `make` and `htpasswd` (`apache2-utils`) installed

## Quick Start

### 1. Configure

```bash
cp .env.example .env
```

Edit `.env` — at minimum set:

- `DOMAIN` — your internal domain (e.g. `infra.local`)
- `HOST_IP` — server's LAN IP address
- All `*_PASSWORD` variables — use strong, unique passwords

### 2. Bootstrap (run once)

```bash
make init
```

This creates the `infra_net` Docker network, all data directories, and initializes Step CA. The CA root certificate fingerprint is written back into `.env` automatically.

### 3. Generate Traefik dashboard password

```bash
htpasswd -nB admin | sed 's/\$/\$\$/g'
# Paste the output into core/config/traefik/dynamic/.htpasswd
```

### 4. Start core services

```bash
make core
```

Then open `http://HOST_IP:5380` (Technitium DNS) and:
- Create a zone for your internal domain (e.g. `infra.local`)
- Add an A-record `*.infra.local` → `HOST_IP` (wildcard)
- Set upstream forwarders (e.g. `1.1.1.1`, `8.8.8.8`)

Point your devices' DNS to `HOST_IP`.

### 5. Start identity (SSO)

```bash
make identity
```

Open `https://auth.infra.local` and complete the Authentik setup wizard. Then:
- Create OIDC/OAuth2 provider applications for each service you plan to run
- Copy the generated client ID and secret into `.env` for the corresponding service

### 6. Start remaining services

Services are independent — start only what you need:

```bash
make vpn
make git
make files
make mail
make calendar
make messenger
make monitoring
```

Or start everything at once:

```bash
make up-all
```

## Service Trust Model

Service trust is managed by **Step CA** with two mechanisms:

1. **Short-lived TLS certificates (24h)** — issued via ACME. A service that is decommissioned stops renewing and its cert expires within 24h implicitly. No revocation list needed.
2. **OIDC provisioner** — Step CA can be configured to require Authentik authentication before issuing a certificate, binding service identity to the SSO layer.

For immediate revocation, Step CA also supports CRL and OCSP endpoints.

## Adding a New Service

1. Create a new directory and `docker-compose.yml`
2. Attach the service to `infra_net` (`networks: [infra_net]` + `external: true`)
3. Add Traefik labels for routing and TLS
4. Add a DNS record in Technitium
5. (Optional) Create an OIDC app in Authentik for SSO
6. `docker compose -f <service>/docker-compose.yml --env-file .env up -d`

No other services need to be modified or restarted.

## Post-Install Checklist

- [ ] `.env` — all passwords set, `HOST_IP` and `DOMAIN` correct
- [ ] `core/config/traefik/dynamic/.htpasswd` — real bcrypt hash for Traefik dashboard
- [ ] Technitium — internal zone and wildcard A-record created
- [ ] Authentik — initial setup complete, OIDC apps created per service
- [ ] Woodpecker — OAuth app created in Forgejo UI (`git.infra.local` → Settings → Applications), client ID/secret in `.env`
- [ ] WireGuard — `WG_PASSWORD_HASH` set (bcrypt of chosen password; see [wg-easy docs](https://github.com/wg-easy/wg-easy))
- [ ] Dendrite — Matrix signing key generated and mounted (see `messenger/config/dendrite/dendrite.yaml`)
- [ ] Mail DNS — SPF, DKIM, DMARC records configured in your public DNS if sending external mail

## Makefile Reference

```
make help         Show all available targets
make init         Bootstrap: network, data dirs, Step CA
make core         Start Traefik + Step CA + DNS
make identity     Start Authentik
make vpn          Start WireGuard
make git          Start Forgejo + Woodpecker
make files        Start SFTPGo
make mail         Start Stalwart Mail
make calendar     Start Radicale
make messenger    Start Dendrite + Element Web
make monitoring   Start Prometheus + Grafana + Loki
make up-all       Start all services in order
make down-all     Stop all services
make ps           Show running containers
make logs SVC=X   Tail logs for a service group (e.g. SVC=core)
```

## Security Notes

- All service-to-browser traffic is TLS-encrypted (certificates from internal Step CA)
- HTTP is automatically redirected to HTTPS by Traefik
- Security headers (HSTS, X-Frame-Options, etc.) are applied globally via Traefik middleware
- Secrets are in `.env` which is gitignored — never commit it
- The `data/` directory is gitignored — contains all persistent service data
