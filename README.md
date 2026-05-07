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

### Installing prerequisites (Debian / Ubuntu / Raspberry Pi OS)

```bash
# System update
sudo apt update && sudo apt upgrade -y

# Basic tools
sudo apt install -y make curl git openssl apache2-utils

# Docker Engine + Compose plugin (official repo)
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

# Allow your user to run Docker without sudo
sudo usermod -aG docker $USER
newgrp docker
```

> **Ubuntu** users: replace `/linux/debian` with `/linux/ubuntu` in the repo URL above.  
> **Raspberry Pi OS** is Debian-based — use the `debian` URL with `arm64` or `armhf` architecture.

Verify the install:

```bash
docker version          # should show Engine 25+
docker compose version  # should show v2+
make --version
htpasswd                # should print usage (from apache2-utils)
```

## Quick Start

### 1. Run the interactive setup wizard

```bash
make setup
```

This single command:
1. Checks prerequisites (`docker`, `openssl`)
2. Prompts for your domain, server IP, and all service passwords (each confirmed by typing twice, minimum 12 characters)
3. Auto-generates all cryptographic secrets (`AUTHENTIK_SECRET_KEY`, `WOODPECKER_AGENT_SECRET`, WireGuard bcrypt hash)
4. Writes a complete `.env` file
5. Creates the `infra_net` Docker network and all data directories
6. Initialises Step CA and writes its root certificate fingerprint back into `.env`
7. Generates the Dendrite Matrix signing key
8. Writes the Traefik dashboard `htpasswd` entry

If `.env` already exists, the wizard offers to re-run, skip to init, or quit.

### 2. Start core services

```bash
make core
```

Then open `http://HOST_IP:5380` (Technitium DNS) and:
- Create a zone for your internal domain (e.g. `infra.local`)
- Add an A-record `*.infra.local` → `HOST_IP` (wildcard)
- Set upstream forwarders (e.g. `1.1.1.1`, `8.8.8.8`)

Point your devices' DNS to `HOST_IP`.

### 3. Start identity (SSO)

```bash
make identity
```

Open `https://auth.infra.local` and complete the Authentik setup wizard.

### 4. Start remaining services

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

Or start all enabled scopes in dependency order:

```bash
make scope-all
```

### 5. Configure OIDC integrations

After services are running, create OIDC apps in Authentik and the Forgejo OAuth app for Woodpecker, then run:

```bash
make configure-oidc
```

This interactive script walks through each integration, shows you exactly where to find each token in the UI, and writes the values into `.env`. Restart the affected services afterwards.

## Service Trust Model

Service trust is managed by **Step CA** with two mechanisms:

1. **Short-lived TLS certificates (24h)** — issued via ACME. A service that is decommissioned stops renewing and its cert expires within 24h implicitly. No revocation list needed.
2. **OIDC provisioner** — Step CA can be configured to require Authentik authentication before issuing a certificate, binding service identity to the SSO layer.

For immediate revocation, Step CA also supports CRL and OCSP endpoints.

## Scopes

Services are grouped into **scopes** — logical deployment units with declared dependencies. The scope system lets you deploy only what you need and ensures services start in the correct order.

### Available scopes

| Scope | Services | Hard deps | Soft deps |
|---|---|---|---|
| `network` | Traefik, Step CA, Technitium DNS, WireGuard | — | — |
| `identity` | Authentik (SSO/OIDC) | network | — |
| `dev` | Forgejo, Woodpecker CI | network | identity |
| `productivity` | SFTPGo, Stalwart Mail, Radicale | network | identity |
| `communication` | Dendrite, Element Web | network | identity |
| `observability` | Prometheus, Loki, Grafana | network | identity |

> **Hard dependency**: the dependent scope will refuse to start if the required scope's health check fails.  
> **Soft dependency**: a warning is printed, but startup continues (reduced functionality — e.g. no OIDC login).  
> **Special case**: Radicale (calendar) uses Authentik forward-auth middleware. `setup.sh` automatically enables the `identity` scope when `productivity` is selected.

### Dependency graph

```
network (always first)
  ├── identity
  │     └── (soft dep of: dev, productivity, communication, observability)
  ├── dev
  ├── productivity
  ├── communication
  └── observability
```

### Scope selection

`make setup` presents an interactive scope selection menu. Your choices are saved as `ENABLED_SCOPES` in `.env`. Only passwords and secrets relevant to enabled scopes are prompted.

To change your scope selection later, re-run `make setup` (choose **[r]** at the resume prompt) or edit `ENABLED_SCOPES` in `.env` and re-run `make init`.

### Scope make targets

```
make scope-network        Start network scope (no dep check)
make scope-identity       Start identity scope (checks: network healthy)
make scope-dev            Start dev scope (checks: network; warns if no identity)
make scope-productivity   Start productivity scope (checks: network; warns if no identity)
make scope-communication  Start communication scope (checks: network; warns if no identity)
make scope-observability  Start observability scope (checks: network; warns if no identity)
make scope-all            Start all ENABLED_SCOPES in dependency order
make scope-down-all       Stop all ENABLED_SCOPES in reverse order
make scope-status         Show live health check results for all enabled scopes
```

## Adding a New Service

1. Create a new directory and `docker-compose.yml`
2. Attach the service to `infra_net` (`networks: [infra_net]` + `external: true`)
3. Add Traefik labels for routing and TLS
4. Add a DNS record in Technitium
5. (Optional) Create an OIDC app in Authentik for SSO
6. `docker compose -f <service>/docker-compose.yml --env-file .env up -d`

No other services need to be modified or restarted.

## Post-Install Checklist

- [ ] `make setup` completed — `.env` written with no placeholder values
- [ ] Technitium DNS — internal zone and wildcard A-record created
- [ ] Authentik — initial setup complete
- [ ] `make configure-oidc` run — all OIDC tokens filled in
- [ ] Services restarted after `configure-oidc`
- [ ] Mail DNS — SPF, DKIM, DMARC records configured in your public DNS if sending external mail

## Makefile Reference

```
make help                 Show all available targets
make setup                Interactive wizard: scope selection, prompts, secrets, writes .env, calls init
make init                 Non-interactive bootstrap (requires existing .env)
make configure-oidc       Fill in post-UI OIDC tokens interactively

# Scope targets (dependency-aware — preferred over individual targets)
make scope-network        Start Traefik + Step CA + DNS + WireGuard
make scope-identity       Start Authentik (checks network healthy first)
make scope-dev            Start Forgejo + Woodpecker CI
make scope-productivity   Start SFTPGo + Stalwart Mail + Radicale
make scope-communication  Start Dendrite + Element Web
make scope-observability  Start Prometheus + Grafana + Loki
make scope-all            Start all enabled scopes in dependency order
make scope-down-all       Stop all enabled scopes in reverse order
make scope-status         Show live health status of all enabled scopes

# Individual targets (no dependency checking)
make core                 Start Traefik + Step CA + DNS
make identity             Start Authentik
make vpn                  Start WireGuard
make git                  Start Forgejo + Woodpecker
make files                Start SFTPGo
make mail                 Start Stalwart Mail
make calendar             Start Radicale
make messenger            Start Dendrite + Element Web
make monitoring           Start Prometheus + Grafana + Loki
make up-all               Start all services in order
make down-all             Stop all services
make ps                   Show running containers
make logs SVC=X           Tail logs for a service group (e.g. SVC=core)
```

## Security Notes

- All service-to-browser traffic is TLS-encrypted (certificates from internal Step CA)
- HTTP is automatically redirected to HTTPS by Traefik
- Security headers (HSTS, X-Frame-Options, etc.) are applied globally via Traefik middleware
- Secrets are in `.env` which is gitignored — never commit it
- The `data/` directory is gitignored — contains all persistent service data

## Future: Horizontal Scaling (Docker Swarm)

The current architecture uses Docker Compose and is intentionally scoped to a single-node deployment. The design is Swarm-ready and the migration would require minimal changes:

| Current (Compose) | Swarm equivalent |
|---|---|
| `docker network create infra_net` | `docker network create --driver overlay infra_net` |
| `docker compose ... up -d` | `docker stack deploy -c compose.yml stack_name` |
| `.env` file bind-mounted | Docker Secrets (`docker secret create`) |
| Traefik Docker provider | Traefik Docker Swarm provider (one label change) |

What would change:
- **Networking**: switch from bridge to overlay network (one flag)
- **Secrets**: migrate plaintext `.env` values to Docker Secrets
- **Traefik**: enable Swarm mode (`swarmMode: true`) + add `deploy.labels` in compose files
- **Placement constraints**: pin stateful services (databases, Step CA) to manager or labelled nodes
- **Storage**: replace bind mounts with named volumes or a distributed storage driver (NFS, GlusterFS, etc.)

This is reserved for a future iteration. The current single-node setup handles typical small-team workloads and is straightforward to migrate when horizontal scaling becomes necessary.
