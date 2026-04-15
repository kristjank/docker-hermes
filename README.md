# docker-hermes

Docker image for [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) — run it in a container and pick up where you left off.

## Quick start

```bash
cp .env.example .env
# edit .env and add at least one model API key

docker compose build
docker compose run --rm hermes
```

That drops you into the `hermes` interactive CLI. Exit with Ctrl-D; your skills, history, and config are persisted in the `hermes-home` volume, so the next `docker compose run` resumes the same state.

## Layout

- **[Dockerfile](Dockerfile)** — Python 3.11 + Node 22 + uv + Playwright chromium; clones the repo at build time and installs `.[all]` extras into `/opt/hermes-venv`.
- **[docker-compose.yml](docker-compose.yml)** — interactive TTY, `.env` injection, named volume on `~/.hermes`.
- **[.env.example](.env.example)** — API key scaffold.

## Common tweaks

**Skip Playwright (~400 MB smaller, no browser tools):**
```bash
docker compose build --build-arg INSTALL_PLAYWRIGHT=0
```

**Pin to a specific hermes-agent commit:**
```bash
docker compose build --build-arg HERMES_REF=<sha>
```

**Minimal install** (drop the `[all]` extras — no matrix, voice, modal, etc.):
```bash
docker compose build --build-arg INSTALL_EXTRAS=.
```

**Run a non-interactive one-shot:**
```bash
docker compose run --rm hermes -p "summarize the README in one line"
```

**Mount a host project for hermes to work on:**
Uncomment the `./workspace:/home/hermes/workspace` line in `docker-compose.yml`.

## Updating

```bash
docker compose build --no-cache    # re-clone at current HERMES_REF
```

The `hermes-home` volume is untouched, so skills/config carry over.

## Notes

- The container runs as non-root user `hermes` (uid 1000).
- Voice input (microphone) and GPU acceleration are **not** wired up — those need host-device passthrough, which is platform-specific. The CLI, tools, and browser agent all work as-is.
- Matrix e2e encryption requires Linux; it's included in `[all]` but guarded by a platform marker upstream.
