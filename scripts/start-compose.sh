#!/bin/zsh

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin:$PATH"

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
MAX_RETRIES=120
RETRY_DELAY=3

cd "$PROJECT_DIR"

if ! command -v docker >/dev/null 2>&1; then
  print -u2 "docker command not found in PATH: $PATH"
  exit 1
fi

typeset -i retries=0
until docker info >/dev/null 2>&1; do
  retries+=1

  if (( retries >= MAX_RETRIES )); then
    print -u2 "Docker daemon did not become ready within $((MAX_RETRIES * RETRY_DELAY)) seconds."
    exit 1
  fi

  sleep "$RETRY_DELAY"
done

DOCKER_CONTEXT=$(docker context show 2>/dev/null || print "unknown")
print "[$(date '+%Y-%m-%d %H:%M:%S')] docker context: $DOCKER_CONTEXT"
print "[$(date '+%Y-%m-%d %H:%M:%S')] running docker compose up -d in $PROJECT_DIR"

docker compose up -d
