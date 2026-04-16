# docker-hermes

Containerized [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) — Docker Compose setup with a friendly wrapper script. Run the agent in a terminal, keep a messaging gateway running in the background, and persist all state across rebuilds.

```bash
./hermes open        # interactive terminal UI
./hermes start       # background messaging gateway
./hermes env         # edit API keys
./hermes help        # full command list
```

---

## What you get

- **Two services sharing one volume and one workspace.** An interactive TUI (`hermes` service) and a long-running messaging listener (`gateway` service) that both see the same config, skills, conversation history, and `./workspace/` directory.
- **Bidirectional file I/O via `./workspace/`.** Anything hermes writes (PDFs, reports, downloads) lands in `./workspace/` on your host. Anything you drop into `./workspace/` is visible inside the agent at `/home/hermes/workspace`.
- **Everything in one volume.** API keys, hermes config, skills, sessions, and memories live in a named Docker volume. Rebuild the image, reinstall your laptop, whatever — the volume carries your state forward.
- **One wrapper script.** `./hermes` is a thin bash layer over `docker compose` with verbs like `open` / `start` / `stop` / `env` / `logs` / `backup`.
- **No secrets on the host filesystem.** The host `.env` is intentionally empty; credentials live inside the persistent volume.

---

## Prerequisites

- **Docker Desktop** (macOS / Windows) or Docker Engine + Compose v2 (Linux). Tested with Docker Desktop 4.x on macOS.
- **At least one model API key.** Anthropic, OpenAI, OpenRouter, Mistral, or any OpenAI-compatible endpoint (including local llama.cpp / vLLM / Ollama).
- Disk space: **~3 GB** for the full image with Playwright, **~1.5 GB** without.
- First build takes **3–5 minutes** (clones hermes-agent, installs `.[all]` extras, downloads Playwright chromium).

---

## Quick start

```bash
git clone <this-repo> docker-hermes
cd docker-hermes

./hermes build                  # first build, cached after
./hermes setup                  # interactive wizard — pick a provider, paste an API key
./hermes open                   # say hi
```

The wizard writes your API key into the volume at `~/.hermes/.env` (inside the container). There is no host-side `.env` file at all — all state lives in the Docker volume.

---

## The `./hermes` wrapper

```
agent:
  open              launch the interactive terminal UI
  shell             bash shell inside a one-off container
  config [args]     run `hermes config …` in a one-off container
  edit              open config.yaml (model/tools/personalities)
  env               edit the volume's .env (API keys, tokens)
  cat-env           list which keys exist (values redacted)
  setup             run the first-time setup wizard
  gsetup            run the gateway-specific setup wizard

gateway (background messaging listener):
  start             bring gateway up in background
  stop              stop the gateway
  restart           restart the gateway
  status            show running services
  logs [args]       follow gateway logs (pass extra args verbatim)

image / volume:
  build             build the image (cached)
  rebuild           build with --no-cache
  update            re-clone latest hermes-agent and rebuild
  clean             remove containers (keep the hermes-home volume)
  nuke              remove containers AND the volume (destructive)
```

Invoke as `./hermes <command>`. Any extra args after the command are forwarded verbatim to `docker compose`.

---

## Configuration

### Where keys live

| Location | Holds | How to edit |
|---|---|---|
| **Volume `.env`** (`~/.hermes/.env` in container) | All API keys, tokens, `HERMES_MAX_ITERATIONS` | `./hermes env` or `./hermes setup` |
| **Volume `config.yaml`** (`~/.hermes/config.yaml`) | Default model, providers, tools, personalities | `./hermes edit` |

For boot-time env vars (e.g. `TZ`, `HTTP_PROXY`) that need to be set before hermes starts, add an `environment:` block under the relevant service in `docker-compose.yml`, or create a `docker-compose.override.yml` (gitignored) with your local overrides.

### Adding an API key

```bash
./hermes env         # opens vi on ~/.hermes/.env in a disposable alpine container
```

Add a line like `OPENAI_API_KEY=sk-…` and save. The gateway auto-restarts to pick it up. To see which keys are configured (values redacted):

```bash
./hermes cat-env
```

### Switching or adding LLM providers

**Interactive (easiest) — inside the TUI:**

```bash
./hermes open
# then in the chat prompt:
/model
```

Menu lets you pick a provider, paste keys, set as default.

**OpenAI-compatible cloud (OpenRouter, Mistral, z.ai, Moonshot, MiniMax, Nous Portal, etc.):**

Add keys to `./hermes env`. The provider is auto-detected from the key prefix; `/model <provider>:<name>` switches default.

**Local or self-hosted OpenAI-compatible endpoint** (llama.cpp, vLLM, Ollama, a remote GPU workstation):

Edit `config.yaml` directly:

```bash
./hermes edit
```

Add a custom provider block and point `model:` at it:

```yaml
custom_providers:
  - name: my-llm                                    # any label
    base_url: http://my-host.example.com:8080/v1    # OpenAI-compatible /v1
    api_key: dummy                                  # required field; use a real key if your server requires auth
    models:
      - gemma-4                                     # list all models this endpoint serves

model:
  provider: my-llm
  default: gemma-4

fallback_model:                                     # used when the primary is unreachable
  provider: anthropic
  model: claude-opus-4-6
```

Save, gateway auto-restarts, and you're routing to your endpoint.

**Local Ollama on the same Mac:** use `base_url: http://host.docker.internal:11434/v1` — `host.docker.internal` resolves to your host from inside containers on Docker Desktop.

**Remote endpoint over Tailscale:** just use the tailnet hostname (`http://hostname.tailnet-name.ts.net:8080/v1`). Docker Desktop on macOS resolves `.ts.net` via the host's Tailscale DNS and routes tailnet traffic through the host's `utun` interface automatically. If connections time out on first use, that's often a cold Tailscale peer — the second attempt will work.

### Messaging gateway

Hermes can listen on Telegram, Discord, Slack, WhatsApp, Signal, and Email from one long-running process. First-time config:

```bash
./hermes gsetup      # interactive: pick platforms + paste bot tokens
./hermes start       # run the listener in the background
./hermes logs        # follow its output
```

- **Polling/socket modes (Telegram, Discord, Slack Socket Mode)** — outbound-only, nothing to expose.
- **Webhook modes (Telegram webhook, Slack HTTP mode, WhatsApp Business)** — need inbound HTTPS. Uncomment the `ports:` block in `docker-compose.yml` and put a reverse proxy (Caddy, Cloudflare Tunnel, ngrok) in front.

Stop/start the gateway at any time with `./hermes stop` / `./hermes start`. Your configuration persists in the volume.

---

## File I/O — the `./workspace/` directory

The `hermes` and `gateway` services run with `working_dir: /home/hermes/workspace`, which is bind-mounted from `./workspace/` in the repo. This is where you exchange files with the agent.

```bash
# Drop a file for hermes to read
cp ~/Downloads/contract.pdf ./workspace/
./hermes open
# In the TUI:  "read workspace/contract.pdf and summarize it"

# Pick up a file hermes generated
ls ./workspace/
```

Why it's mounted there:

- Hermes's `write_file` tool, shell commands, and tool outputs default to the current working directory.
- `./workspace/` is both persistent (lives on your host filesystem, not in an ephemeral container) and **directly accessible** from your host without `docker cp` or volume-extraction commands.
- The messaging gateway shares the same workspace, so files generated from a Telegram/Discord chat land in the same place.

The workspace directory is **gitignored** — nothing in it ever gets committed. Treat it like `~/Downloads`: disposable working scratch space that's yours to organize.

If you want hermes to work on your actual projects, either copy files in, or add additional bind mounts under `volumes:` in `docker-compose.yml`.

---

## State management

### What lives in the volume

```
~/.hermes/
├── .env              # API keys
├── config.yaml       # model/provider/tool/personality config
├── sessions/         # conversation history (SQLite + FTS5 search)
├── memories/         # long-term memory
├── skills/           # user + agent-created skills
├── cron/             # scheduled automations
├── logs/             # runtime logs
├── hooks/            # user-defined hooks
├── pairing/          # DM pairing tokens for messaging platforms
├── platforms/        # per-platform state (telegram, discord, slack…)
├── image_cache/
├── audio_cache/
└── state.db*         # persistent agent state
```

The hermes-agent source and Python venv live at `/opt/hermes-agent` and `/opt/hermes-venv` *inside the image* — rebuilding the image does not touch the volume.

### What survives what

| Action | Volume | Image | Containers |
|---|---|---|---|
| `./hermes stop` / `restart` | ✓ | ✓ | recreated |
| `./hermes clean` | ✓ | ✓ | removed |
| `./hermes update` / `rebuild` | ✓ | rebuilt | removed |
| `./hermes nuke` | **deleted** | ✓ | removed |
| `docker system prune -a --volumes` | **deleted** | rebuilt | removed |

### Backup

```bash
docker run --rm \
    -v docker-hermes_hermes-home:/src \
    -v "$PWD":/dst \
    alpine tar czf /dst/hermes-backup-$(date +%F).tar.gz -C /src .
```

### Restore

```bash
docker run --rm \
    -v docker-hermes_hermes-home:/dst \
    -v "$PWD":/src \
    alpine tar xzf /src/hermes-backup-2026-04-15.tar.gz -C /dst
```

### Inspect the volume

```bash
./hermes shell                                          # bash inside a new container
# then: ls -la ~/.hermes

docker volume inspect docker-hermes_hermes-home         # on-disk location
```

---

## Updating hermes-agent

The image clones `NousResearch/hermes-agent` at build time. To update:

```bash
./hermes update      # equivalent to `docker compose build --no-cache`
```

The volume is untouched. If the TUI prints "N commits behind — run hermes update", that's telling you about this — run `./hermes update` from outside the container, not `hermes update` inside it.

### Pinning to a specific commit

For reproducibility:

```bash
./hermes build --build-arg HERMES_REF=<sha>
```

Or set it permanently in `docker-compose.yml` under `services.hermes.build.args.HERMES_REF`.

---

## Build tweaks

All controlled via build args in `docker-compose.yml` → `services.hermes.build.args`, or passed to `./hermes build --build-arg KEY=value`:

| Arg | Default | Effect |
|---|---|---|
| `HERMES_REF` | `main` | Git ref (branch, tag, or SHA) to clone |
| `INSTALL_PLAYWRIGHT` | `1` | Set to `0` to skip chromium (~400 MB smaller, disables browser tools) |
| `INSTALL_EXTRAS` | `.[all]` | Python extras to install. Minimal: `.` Mid: `.[messaging,cron,cli,pty,mcp,honcho,acp,web]` |

---

## Networking

- **DNS from inside the container** — uses Docker's embedded resolver, which forwards to the host's system resolver. Works for public DNS, Tailscale MagicDNS, and mDNS on most setups.
- **Reaching services on the host** — use `host.docker.internal` (Docker Desktop convenience hostname). Don't use `localhost` or `127.0.0.1` inside the container — those refer to the container itself.
- **Reaching other LAN hosts** — regular IPs/hostnames work; Docker Desktop NATs container traffic through the host.
- **Reaching Tailscale peers** — works transparently on Docker Desktop for Mac/Windows. The host's Tailscale tun interface routes `100.x.x.x/10` packets; container traffic for those IPs flows through the host. If peers are idle they may take a second to wake.
- **Inbound from the internet** (webhook modes) — uncomment `ports:` in `docker-compose.yml` and terminate TLS in front (Caddy, Cloudflare Tunnel, etc.).

---

## Security notes

- **Never commit your volume `.env`.** It's not checked in by design — it lives inside Docker's managed volumes, not the repo.
- **No host-side `.env`.** There's nowhere on your host filesystem to accidentally paste credentials — `.gitignore` still blocks `.env` in case you create one, but compose doesn't expect it.
- **If a key ever shows up in a terminal transcript, screenshot, or log paste, rotate it.** Providers make rotation a 60-second affair.
- **The container runs as non-root** (uid 1000). `docker run` flags like `--privileged` or bind-mounts to host-sensitive paths are not used.
- **For messaging gateways**, hermes supports DM pairing and command approval — run `./hermes gsetup` and review the security sections in the upstream docs: https://hermes-agent.nousresearch.com/docs/user-guide/security

---

## Troubleshooting

**`No editor found. Config file is at: /home/hermes/.hermes/config.yaml`**
`./hermes edit` uses a disposable alpine container with `vi` against the volume, so this shouldn't happen. If it does, you're probably calling raw `hermes config edit` inside a running container — use the wrapper instead.

**`PermissionError: [Errno 13] Permission denied: '/home/hermes/.hermes/cron'`**
A named volume was created before the image baked in the directory with correct uid. Fix: `./hermes nuke` (destroys volume — only do this if you haven't configured anything yet), then `./hermes build` + `./hermes setup`.

**Gateway times out / crashes immediately after `./hermes start`**
`./hermes logs` shows why. Most common cause: a missing or invalid token for one of the platforms you enabled. Re-run `./hermes gsetup` to fix.

**First Tailscale request from container times out**
Tailscale peer is cold. Retry once; subsequent requests work. Fallback model (if configured) handles this gracefully for end users.

**"N commits behind"**
Run `./hermes update` from outside the container (not `hermes update` from inside).

**Volume corruption / want a clean slate**
```bash
./hermes nuke           # destroys the volume (asks for confirmation)
./hermes build
./hermes setup
```

---

## File layout

- **[Dockerfile](Dockerfile)** — Python 3.11 + Node 22 + uv. Clones hermes-agent at build time, installs extras into `/opt/hermes-venv`, installs Playwright chromium. Non-root user `hermes` (uid 1000), `tini` as PID 1 for clean signal handling.
- **[docker-compose.yml](docker-compose.yml)** — two services (`hermes` TUI, `gateway` daemon) on one named volume.
- **[hermes](hermes)** — bash wrapper around docker compose; self-documenting via `./hermes help`.
- **[.gitignore](.gitignore)** — blocks `.env` (in case you ever create one), workspace mounts, backup tarballs, macOS/editor noise.

---

## Upstream references

- **Hermes Agent:** https://github.com/NousResearch/hermes-agent
- **Docs:** https://hermes-agent.nousresearch.com/docs
- **CLI guide:** https://hermes-agent.nousresearch.com/docs/user-guide/cli
- **Messaging gateway:** https://hermes-agent.nousresearch.com/docs/user-guide/messaging
- **Security:** https://hermes-agent.nousresearch.com/docs/user-guide/security

---

## License

Hermes Agent itself is MIT-licensed upstream. This wrapper repo follows the same license unless you add your own.
