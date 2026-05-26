#!/usr/bin/env bash
set -euo pipefail

IMAGE="${DOTFILES_TEST_IMAGE:-dotfiles-ubuntu-manual:24.04}"
CONTAINER="${DOTFILES_TEST_CONTAINER:-dotfiles-manual}"
REPO_URL="${DOTFILES_REPO_URL:-https://github.com/gausshj/dotfiles.git}"
BRANCH="${DOTFILES_BRANCH:-}"
PROXY="${DOTFILES_TEST_PROXY:-}"
TIMEZONE="${DOTFILES_TEST_TZ:-${TZ:-}}"

if [[ -z "$BRANCH" ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BRANCH="$(git branch --show-current)"
fi
BRANCH="${BRANCH:-main}"

if [[ -z "$TIMEZONE" && -L /etc/localtime ]]; then
    LOCALTIME_LINK="$(readlink /etc/localtime || true)"
    case "$LOCALTIME_LINK" in
        *zoneinfo/*)
            TIMEZONE="${LOCALTIME_LINK#*zoneinfo/}"
            ;;
    esac
fi
TIMEZONE="${TIMEZONE:-Etc/UTC}"

usage() {
    cat <<USAGE
Usage: scripts/manual-test-docker.sh [options]

Options:
  --branch NAME       Git branch used by the curl install command.
  --repo URL          Git repository cloned by install.sh.
  --proxy URL         Proxy for apt, curl, and git inside Docker.
  --timezone NAME     IANA timezone for the test container.
  --image NAME        Local Docker image name.
  --container NAME    Container name.
  -h, --help          Show this help.

Environment equivalents:
  DOTFILES_BRANCH, DOTFILES_REPO_URL, DOTFILES_TEST_PROXY,
  DOTFILES_TEST_TZ, DOTFILES_TEST_IMAGE, DOTFILES_TEST_CONTAINER
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --repo)
            REPO_URL="$2"
            shift 2
            ;;
        --proxy)
            PROXY="$2"
            shift 2
            ;;
        --timezone)
            TIMEZONE="$2"
            shift 2
            ;;
        --image)
            IMAGE="$2"
            shift 2
            ;;
        --container)
            CONTAINER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

echo "==> Building reusable Ubuntu manual-test image: $IMAGE"
echo "==> Test container timezone: $TIMEZONE"
docker build \
    --build-arg HTTP_PROXY="$PROXY" \
    --build-arg HTTPS_PROXY="$PROXY" \
    --build-arg http_proxy="$PROXY" \
    --build-arg https_proxy="$PROXY" \
    --build-arg TZ="$TIMEZONE" \
    -t "$IMAGE" - <<'DOCKERFILE'
FROM ubuntu:24.04

ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG http_proxy
ARG https_proxy
ARG TZ=Etc/UTC

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=${TZ}
ENV HTTP_PROXY=${HTTP_PROXY}
ENV HTTPS_PROXY=${HTTPS_PROXY}
ENV http_proxy=${http_proxy}
ENV https_proxy=${https_proxy}

RUN apt-get -o Acquire::Retries=5 update \
    && apt-get -o Acquire::Retries=5 install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        locales \
        sudo \
    && locale-gen en_US.UTF-8 \
    && useradd -m -s /bin/bash gausshj \
    && printf 'gausshj:gausshj\n' | chpasswd \
    && mkdir -p /etc/sudoers.d \
    && printf 'Defaults env_keep += "DEBIAN_FRONTEND TZ"\n' > /etc/sudoers.d/dotfiles-env \
    && printf 'gausshj ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/gausshj \
    && chmod 0440 /etc/sudoers.d/dotfiles-env \
    && chmod 0440 /etc/sudoers.d/gausshj \
    && rm -rf /var/lib/apt/lists/*

RUN printf '%s\n' \
    '#!/usr/bin/env bash' \
    'cat <<HELP' \
    'Manual dotfiles test container is ready.' \
    '' \
    'Login:' \
    '  user: gausshj' \
    '  password: gausshj' \
    '  sudo does not ask for a password in this test container' \
    '  timezone: ${TZ}' \
    '' \
    'Recommended commands:' \
    '  test-local    # cd /workspace/dotfiles && ./bootstrap.sh' \
    '  test-curl     # curl install.sh from DOTFILES_BRANCH' \
    '' \
    'Raw commands:' \
    '  cd /workspace/dotfiles && ./bootstrap.sh' \
    '  curl -fsSL https://github.com/gausshj/dotfiles/raw/${DOTFILES_BRANCH}/install.sh | bash' \
    '' \
    'After install checks:' \
    '  nvim --headless "+qall"' \
    '  tmux -f ~/.tmux.conf new-session -d -s smoke && tmux kill-session -t smoke' \
    '' \
    'Container lifecycle:' \
    '  docker start -ai ${DOTFILES_TEST_CONTAINER:-dotfiles-manual}' \
    '  docker rm -f ${DOTFILES_TEST_CONTAINER:-dotfiles-manual}' \
    'HELP' \
    > /usr/local/bin/dotfiles-test-help \
    && chmod +x /usr/local/bin/dotfiles-test-help

USER gausshj
WORKDIR /home/gausshj
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TERM=xterm-256color
ENV COLORTERM=truecolor
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=${TZ}

RUN printf '%s\n' \
    'alias test-local="cd /workspace/dotfiles && ./bootstrap.sh"' \
    'alias test-curl="curl -fsSL https://github.com/gausshj/dotfiles/raw/${DOTFILES_BRANCH}/install.sh | bash"' \
    '' \
    'if [ -t 1 ] && command -v dotfiles-test-help >/dev/null 2>&1; then' \
    '  dotfiles-test-help' \
    'fi' \
    >> /home/gausshj/.bashrc
DOCKERFILE

echo "==> Starting interactive container: $CONTAINER"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

docker run \
    --name "$CONTAINER" \
    --hostname dotfiles-test \
    --add-host=host.docker.internal:host-gateway \
    -e TERM=xterm-256color \
    -e COLORTERM=truecolor \
    -e LANG=C.UTF-8 \
    -e LC_ALL=C.UTF-8 \
    -e DEBIAN_FRONTEND=noninteractive \
    -e TZ="$TIMEZONE" \
    -e DOTFILES_REPO_URL="$REPO_URL" \
    -e DOTFILES_BRANCH="$BRANCH" \
    -e HTTP_PROXY="$PROXY" \
    -e HTTPS_PROXY="$PROXY" \
    -e http_proxy="$PROXY" \
    -e https_proxy="$PROXY" \
    -v "$PWD":/workspace/dotfiles:ro \
    -it "$IMAGE" bash -lc '
exec bash -l
'
