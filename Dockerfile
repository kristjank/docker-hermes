# Dockerfile for NousResearch/hermes-agent
# https://github.com/NousResearch/hermes-agent
#
# Build:  docker build -t hermes-agent .
# Run:    docker run --rm -it -v hermes-home:/home/hermes/.hermes --env-file .env hermes-agent
#
# Or just use: docker compose run --rm hermes

FROM python:3.11-slim-bookworm

ARG HERMES_REF=main
ARG INSTALL_PLAYWRIGHT=1
ARG INSTALL_EXTRAS=".[all]"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    EDITOR=nano \
    PATH="/home/hermes/.local/bin:/opt/hermes-venv/bin:${PATH}"

# System deps:
#   git           — clone the repo & git-based Python deps
#   build-essential, python3-dev — for packages that build wheels from source
#   libportaudio2 — runtime for sounddevice (voice extra)
#   ffmpeg        — audio conversions used by edge-tts / voice flows
#   ca-certificates, curl, gnupg — for NodeSource + uv installer
#   tini          — clean PID 1 signal handling for the interactive CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        ca-certificates \
        gnupg \
        build-essential \
        python3-dev \
        libportaudio2 \
        ffmpeg \
        tini \
        nano \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# uv — fast Python package manager (matches upstream installer)
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Non-root user — hermes-agent writes to ~/.hermes at runtime
RUN useradd --create-home --shell /bin/bash --uid 1000 hermes \
    && mkdir -p /opt/hermes-venv /opt/hermes-agent \
    && chown -R hermes:hermes /opt/hermes-venv /opt/hermes-agent

USER hermes
WORKDIR /opt/hermes-agent

# Clone at a pinned ref so `docker build --build-arg HERMES_REF=<sha>` is reproducible.
RUN git clone --depth 1 --branch "${HERMES_REF}" \
        https://github.com/NousResearch/hermes-agent.git . \
    || git clone https://github.com/NousResearch/hermes-agent.git . \
    && git -c advice.detachedHead=false checkout "${HERMES_REF}"

# Python env — editable install so `hermes` entry points resolve against the cloned tree.
RUN uv venv /opt/hermes-venv --python 3.11 \
    && uv pip install --python /opt/hermes-venv/bin/python -e "${INSTALL_EXTRAS}"

# Node side — browser tools (Playwright chromium) + anything in package.json.
# Playwright is large (~400MB); set --build-arg INSTALL_PLAYWRIGHT=0 to skip.
USER root
RUN if [ -f package.json ]; then \
        su hermes -c "cd /opt/hermes-agent && npm install --no-audit --no-fund" ; \
    fi \
    && if [ "${INSTALL_PLAYWRIGHT}" = "1" ] && [ -f package.json ]; then \
        su hermes -c "cd /opt/hermes-agent && npx --yes playwright install chromium" ; \
        npx --yes playwright install-deps chromium || true ; \
    fi
USER hermes

# Persistent state lives here — mount a volume to keep skills/config across runs.
# Pre-create the dir as the hermes user so a fresh named volume inherits uid 1000
# ownership (Docker copies the image mountpoint's perms into the empty volume).
RUN mkdir -p /home/hermes/.hermes
VOLUME ["/home/hermes/.hermes"]

# Interactive CLI — tini reaps zombies and forwards Ctrl-C cleanly.
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/hermes-venv/bin/hermes"]
CMD []
