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
  open                         launch the interactive terminal UI
  resume [id]                  resume a session (no id → most recent)
  sessions [N]                 list the N most recent sessions (default 15)
  shell                        bash shell inside a one-off container
  config [args]                run `hermes config …` in a one-off container
  edit                         open config.yaml (model/tools/personalities)
  env                          edit the volume's .env (API keys, tokens)
  cat-env                      list which keys exist (values redacted)
  setup                        run the first-time setup wizard
  gsetup                       run the gateway-specific setup wizard

profiles / souls (multi-persona):
  profile [args]               forward to `hermes profile …` (list/create/use/…)
  soul [profile]               edit SOUL.md (default profile if omitted)
  soul show [profile]          cat SOUL.md to stdout
  soul import <file> [prof]    replace SOUL.md from host file
  soul export <file> [prof]    save SOUL.md to host file

gateway (background messaging listener):
  start                        bring gateway up in background
  stop                         stop the gateway
  restart                      restart the gateway
  status                       show running services
  logs [args]                  follow gateway logs (pass extra args verbatim)

image / volume:
  build                        build the image (cached)
  rebuild                      build with --no-cache
  update                       re-clone latest hermes-agent and rebuild
  clean                        remove containers (keep the hermes-home volume)
  nuke                         remove containers AND the volume (destructive)
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

## Profiles and souls (multiple personas)

Hermes's personas are not just system-prompt switches — they're fully isolated state trees. This section covers the mental model, the anatomy, the wrapper commands, and common workflows.

### Concepts

**Profile** — a self-contained hermes instance. Has its own model configuration, API keys, skills, memories, chat history, scheduled jobs, and gateway connections. Two profiles with different configurations behave like two different agents, even when they share the same Docker container.

**Soul** — the persona prompt, stored as `SOUL.md` inside a profile directory. Hermes reads it at session start and includes it in every system prompt sent to the model. It's the answer to "who are you?" for that profile.

**Active profile** — the profile hermes uses when you run `./hermes open` without specifying one. Set via `./hermes profile use <name>`. Persisted in `~/.hermes/active_profile`.

**Default profile** — a special profile whose files live at the volume root (`~/.hermes/SOUL.md`, `~/.hermes/config.yaml`, etc.) rather than under `~/.hermes/profiles/`. Created automatically by hermes; cannot be deleted. Thinking of it as "profile zero" is accurate — it's just a profile that happens to live at the top level for backward compatibility.

### Anatomy of the volume

```
~/.hermes/                         ← default profile root
├── active_profile                 ← one line: name of currently-active profile
├── SOUL.md                        ← default profile's persona
├── config.yaml                    ← default profile's model + tools config
├── .env                           ← default profile's API keys / platform tokens
├── sessions/                      ← default profile's chat history (SQLite+FTS5)
├── memories/                      ← default profile's long-term memory
├── skills/                        ← default profile's skills
├── cron/                          ← default profile's scheduled jobs
├── platforms/                     ← default profile's gateway runtime state
├── gateway_state.json             ← default profile's gateway PID + status
└── profiles/
    ├── researcher/                ← a named profile
    │   ├── SOUL.md                ← its own persona
    │   ├── config.yaml            ← could use a different model
    │   ├── .env                   ← could use different keys
    │   ├── sessions/              ← its own chat history
    │   ├── memories/              ← its own memory
    │   ├── skills/                ← its own skills
    │   ├── cron/                  ← its own scheduled jobs
    │   ├── platforms/             ← its own gateway state
    │   └── gateway_state.json
    └── coding-buddy/
        └── …                      ← same structure
```

**Switching profiles** changes every file hermes reads at startup — the model it calls, the keys it uses, the skills it offers, the conversations it remembers, the messaging bots it answers on.

### Profile lifecycle

```bash
./hermes profile list                            # table of all profiles with model + gateway status
./hermes profile show <name>                     # details for one profile
./hermes profile create <name>                   # empty profile (no model, no keys)
./hermes profile create <name> --clone           # copies config.yaml + .env + SOUL.md from active
./hermes profile create <name> --clone-all       # full copy (adds skills, memories, sessions, cron, platforms)
./hermes profile use <name>                      # sets active profile (sticky default)
./hermes profile rename <old> <new>
./hermes profile delete <name> --yes             # --yes is required through the wrapper (see below)
./hermes profile export <name>                   # archive to tar.gz for backup/sharing
./hermes profile import <archive.tar.gz>         # restore from archive
```

**`--clone` vs `--clone-all`** — what each copies from the active profile:

| File/dir | `--clone` | `--clone-all` |
|---|---|---|
| `config.yaml` (model, tools) | ✓ | ✓ |
| `.env` (API keys + platform tokens) | ✓ | ✓ |
| `SOUL.md` (persona) | ✓ | ✓ |
| `skills/` | ✗ | ✓ |
| `memories/` | ✗ | ✓ |
| `sessions/` (chat history) | ✗ | ✓ |
| `cron/` | ✗ | ✓ |
| `platforms/` (messaging state) | ✗ | ✓ |
| `gateway_state.json` | ✗ | ✓ |

**When to use what:**
- **Plain `create`** — you want to configure this persona from scratch (different model, different keys).
- **`--clone`** — new persona that reuses your model + keys + default soul, but starts fresh on memory/skills/history. Good for "same brain, different job".
- **`--clone-all`** — fork an existing agent including its learned skills and remembered history. Good for experimenting without disturbing a working persona.

**Active profile caveat:** new profiles created via plain `create` (no `--clone`) have no `config.yaml`. Hermes will prompt "no API keys or providers found" on first launch. Either run `./hermes setup` after `./hermes profile use <name>`, or use `--clone` up-front.

### Souls in detail

#### What a soul does

`SOUL.md` is pure Markdown; hermes reads it at the start of every conversation and prepends it to the model's system prompt. It's not filtered, templated, or transformed — whatever you write is what the model sees. Typical contents: role definition ("you are a DeFi security triage analyst"), behavioral constraints ("never speculate on token prices"), shared context ("our house uses Uniswap v4 hooks"), tool-use guidance, voice/tone instructions.

#### When hermes reads it

- **Every new session** picks up the current `SOUL.md` of the active profile.
- **Resumed sessions** (`hermes --resume <id>`) keep whatever soul was in use when the session started — editing `SOUL.md` mid-session does **not** retroactively change ongoing conversations.
- **The gateway** holds sessions open for incoming messages, so after importing a new soul you need to restart the gateway to pick it up. The wrapper does this automatically on `./hermes soul import`.

#### Import invariant

`./hermes soul import <file> [profile]` replaces **only** the target profile's `SOUL.md`. Its `config.yaml`, `.env`, `skills/`, `sessions/`, and everything else are untouched. You can swap personas freely without losing the profile's model configuration, keys, memory, or history.

#### The `./souls/` convention

The repo has a gitignored `souls/` directory at the top level for host-side soul files. This is where you keep your persona library so:
- Sources live in plain Markdown, version-controlled privately (personas may encode private context or business logic).
- Import is a single command: `./hermes soul import souls/<name>.md [profile]`.
- Sharing a soul with a teammate is just sending them the `.md` file.

```bash
mkdir -p souls
$EDITOR souls/phd-researcher.md
# paste your persona prompt, save
```

### Wrapper command reference

```bash
# Profile management (forwards to `hermes profile …`)
./hermes profile list
./hermes profile show <name>
./hermes profile create <name> [--clone | --clone-all]
./hermes profile use <name>
./hermes profile rename <old> <new>
./hermes profile delete <name> --yes
./hermes profile export <name>
./hermes profile import <archive>

# Soul management (operates on the volume, doesn't require a hermes image rebuild)
./hermes soul [profile]                          # vi edit (active profile if omitted)
./hermes soul show [profile]                     # cat to stdout
./hermes soul import <file> [profile]            # replace from host file
./hermes soul export <file> [profile]            # save to host file
```

With no `[profile]` argument, soul commands target the **active** profile — the one set by `./hermes profile use`. Pass an explicit profile name to override, or `default` to target the volume-root profile.

### End-to-end workflows

#### New persona for a specific project

```bash
# 1. Write the persona on your Mac
$EDITOR souls/phd-researcher.md

# 2. Create a profile that inherits your model + keys
./hermes profile create researcher --clone

# 3. Swap in the custom soul
./hermes soul import souls/phd-researcher.md researcher

# 4. Make it the active profile and start chatting
./hermes profile use researcher
./hermes open
```

#### Separate personas for separate messaging accounts

```bash
# Create two profiles, each with their own Telegram/Slack/Discord bot tokens
./hermes profile create coding-buddy --clone
./hermes profile create researcher   --clone

# For each, edit .env to add platform tokens for that persona's bot
docker run --rm --user 1000:1000 -it -v docker-hermes_hermes-home:/h alpine \
    sh -c 'vi /h/profiles/coding-buddy/.env'

# Import the matching soul
./hermes soul import souls/coding-buddy.md coding-buddy
./hermes soul import souls/researcher.md   researcher

# Start the gateway for the persona you want answering messages right now
./hermes profile use coding-buddy
./hermes start                                   # gateway runs as coding-buddy's bot

# Switch to the other persona later (stops its gateway, starts the new one)
./hermes stop
./hermes profile use researcher
./hermes start
```

Each profile has its own `platforms/` and `gateway_state.json`, so pairings, OAuth refresh tokens, and per-user chat channels are isolated between personas.

#### Sharing a soul with a teammate

```bash
# Export your soul
./hermes soul export souls/coding-buddy.md coding-buddy

# Send souls/coding-buddy.md over any channel — no keys, no history, just persona text.

# They import on their side
./hermes profile create coding-buddy --clone
./hermes soul import souls/coding-buddy.md coding-buddy
```

#### Full profile backup / restore / fork

```bash
# Archive everything (config, keys, soul, skills, memory, sessions, cron) for a profile
./hermes profile export researcher               # → researcher-<timestamp>.tar.gz

# Restore, on same machine or another
./hermes profile import researcher-20260416.tar.gz

# Quick "branch" of an existing persona to experiment without risk
./hermes profile create researcher-v2 --clone-all
# …experiment…
./hermes profile delete researcher-v2 --yes      # discard the fork
```

### Common pitfalls

- **"Model: —" in `profile list`** — profile was created without `--clone` and has no `config.yaml`. Either run `./hermes setup` after `./hermes profile use <name>`, or `./hermes profile delete` and recreate with `--clone`.
- **New soul not taking effect** — if you edited `SOUL.md` during an active conversation (TUI or gateway), existing sessions keep the old soul. Open a new session (Ctrl-D then `./hermes open`) or let the wrapper's auto-restart handle the gateway.
- **`profile delete` cancels immediately** — add `--yes`; the wrapper nudges you with the exact re-run command.
- **Souls committed by mistake** — the repo's `.gitignore` blocks `souls/`. If you ever move the directory or rename it, update the ignore rule accordingly.

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
