<div align="center">

# Sesame

**Your AI agents need secrets. They don't need to see them.**

[![Website](https://img.shields.io/badge/website-getsesame.dev-2563eb?style=flat-square)](https://getsesame.dev)
[![Install](https://img.shields.io/badge/install-curl%20%7C%20sh-22c55e?style=flat-square)](https://getsesame.dev)
[![Contact](https://img.shields.io/badge/contact-hi%40getsesame.dev-64748b?style=flat-square)](mailto:hi@getsesame.dev)

Sesame is a user-controlled broker that proxies authenticated HTTP API calls.<br/>
Your agent calls `sesame request` instead of `curl` — and the broker attaches the right `Authorization` header server-side, based on the target hostname.<br/>
**Credentials never enter the agent's prompt, never appear in logs, never touch agent memory.**

</div>

---

## Why

Modern AI agents need API keys for everything: GitHub, Stripe, OpenAI, Anthropic, your internal services. Today they get those keys via:

- **Environment variables** — leak via logs, prompt injection, or a careless `printenv`.
- **Tool arguments** — same leak surface, one layer deeper.
- **MCP servers with credentials baked in** — the agent can read its own config.

Sesame moves the credential out of the agent's reach entirely. The agent passes a *reference* (the target hostname); the broker — running where you control it — resolves the credential and signs the outbound request. The agent sees only the response body.

## Quickstart

```bash
# Install the CLI (macOS arm64/x86_64, Linux x86_64)
curl -fsSL https://getsesame.dev/install.sh | sh

# Register this device — generates an Ed25519 keypair, opens the
# broker's claim URL in your browser for one-click approval
sesame login

# Make an authenticated request — no API key in sight
sesame request POST https://api.anthropic.com/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model": "claude-sonnet-4-5", "max_tokens": 1024,
       "messages": [{"role": "user", "content": "Hi"}]}'
```

### For AI agents

Drop in the official skill so your agent (Claude Code, Codex, Cursor, OpenClaw, +40 more) reaches for `sesame request` instead of raw `curl` / `fetch` / `requests`:

```bash
npx skills add getsesame/skills --yes --global --all
```

## Commands

| Command | What it does |
|---|---|
| `sesame login` | Register this device with the broker. Generates an Ed25519 keypair, opens a one-click claim URL. |
| `sesame login --new` | Register an additional agent on the same device. |
| `sesame refresh` | Refresh expired tokens via challenge-response with the device key. |
| `sesame status` | Show device fingerprint, registered agents, token state. |
| `sesame switch <agent-id>` | Switch the active agent for this shell. |
| `sesame hostnames` | List hostnames the broker has secrets configured for. |
| `sesame request <METHOD> <URL>` | Proxy an authenticated HTTP request. Supports `-H`, `-d`, `--raw`. |
| `sesame --version` | Print the CLI version. |

## How it works

```
   Agent                    Sesame Broker                  Upstream API
 (no secrets)              (identity & policy)              (Anthropic,
     │                            │                          Stripe, …)
     │  sesame request POST …     │                              │
     ├───────────────────────────►│                              │
     │     (no auth header)       │  ┌── 1. Verify device JWT    │
     │                            │  ├── 2. Look up policy       │
     │                            │  ├── 3. Telegram-approve     │
     │                            │  │      (first hostname)     │
     │                            │  └── 4. Inject Auth header   │
     │                            │                              │
     │                            ├─────────────────────────────►│
     │                            │      (with credential)       │
     │                            │                              │
     │                            │◄─────────────────────────────┤
     │                            │      (response body)         │
     │◄───────────────────────────┤                              │
     │       (response body,      │                              │
     │        no credential)      │                              │
```

The broker is your trust boundary. It enforces:

- **Per-hostname policy**: which methods (`GET`, `POST`, …) and path patterns are allowed for each agent.
- **Just-in-time approval**: first request to a new hostname blocks until you tap *Approve* in the dashboard or Telegram bot. Subsequent requests within the approved window are instant.
- **Instant revocation**: deactivating an agent invalidates all its grants in one click. Replays return `403`.
- **Audit log**: every proxied request, every approval, every revocation, with the credential value redacted everywhere.

## Install options

```bash
# Specific version
curl -fsSL https://getsesame.dev/install.sh | sh -s -- --version v0.3.22

# Custom prefix (default: /usr/local/bin, falls back to ~/.local/bin)
curl -fsSL https://getsesame.dev/install.sh | sh -s -- --prefix ~/.local/bin

# Uninstall
curl -fsSL https://getsesame.dev/install.sh | sh -s -- --uninstall
```

The installer also runs `npx skills add getsesame/skills --yes --global --all` if Node is available, so your AI agents pick up the skill automatically.

## Status

**Pre-1.0.** The end-to-end flow works (broker, CLI, mobile approval, dashboard), and the hosted broker at `getsesame.dev` is live. Treat it as alpha — APIs may change, and we don't yet recommend pushing production secrets through the SaaS until self-host lands.

## Links

- 🌐 [**getsesame.dev**](https://getsesame.dev) — landing page, signup, dashboard
- ✉️ [hi@getsesame.dev](mailto:hi@getsesame.dev) — questions, feedback, security reports
- 🧠 [`getsesame/skills`](https://github.com/getsesame/skills) — the agent skill that wires AI tools into Sesame
