#!/usr/bin/env bash
set -euo pipefail

echo "==> Iniciant tmux-gitops-agent (versió: ${APP_VERSION:-dev})..."

# 1. Confiar en la CA interna (step-ca) si està muntada al sistema
if [ -d /usr/local/share/ca-certificates ] && [ "$(ls -A /usr/local/share/ca-certificates 2>/dev/null)" ]; then
    update-ca-certificates >/dev/null 2>&1 || true
fi

# 2. Preparar directori SSH sense prompts interactius de host key
mkdir -p /root/.ssh && chmod 700 /root/.ssh
ssh-keyscan -H git.rusc.local >> /root/.ssh/known_hosts 2>/dev/null || true

# 3. Identitat Git del compte bot
BOT_USER="${GIT_BOT_NAME:-pi-agent}"
BOT_EMAIL="${GIT_BOT_EMAIL:-pi-agent@rusc.local}"
FORGEJO_HOST="${FORGEJO_URL:-https://git.rusc.local}"

git config --global user.name "$BOT_USER"
git config --global user.email "$BOT_EMAIL"
git config --global init.defaultBranch main
git config --global pull.ff only

# 4. Credencials contra Forgejo (Git + CLI tea)
if [ -n "${FORGEJO_BOT_TOKEN:-}" ]; then
    git config --global credential.helper store
    HOST_NO_PROTO="${FORGEJO_HOST#https://}"
    HOST_NO_PROTO="${HOST_NO_PROTO#http://}"
    echo "https://${BOT_USER}:${FORGEJO_BOT_TOKEN}@${HOST_NO_PROTO}" > /root/.git-credentials
    chmod 600 /root/.git-credentials

    tea login add --name forgejo --url "$FORGEJO_HOST" --token "$FORGEJO_BOT_TOKEN" --no-version-check 2>/dev/null || true
fi

# 5. Clonar repositoris de treball i activar protecció gitleaks
REPOS=(${WORKSPACE_REPOS:-argocd-bootstrap infra docker-server})
mkdir -p /workspace

for repo in "${REPOS[@]}"; do
    if [ ! -d "/workspace/${repo}" ]; then
        git clone "${FORGEJO_HOST}/VDK84/${repo}.git" "/workspace/${repo}" || true
        if [ -d "/workspace/${repo}/.git/hooks" ]; then
            printf '#!/bin/sh\ngitleaks protect --staged --verbose\n' > "/workspace/${repo}/.git/hooks/pre-commit"
            chmod +x "/workspace/${repo}/.git/hooks/pre-commit"
        fi
    fi
done

# 6. Enllaçar memòria persistent des d'infra (si existeix la carpeta al repo)
mkdir -p /root/.pi/agent
if [ -d "/workspace/infra/agent-memory" ]; then
    ln -sfn /workspace/infra/agent-memory /root/.pi/agent/memory
fi

# 7. Deixar la sessió tmux 'agent' aixecada i llesta
tmux has-session -t agent 2>/dev/null || tmux new-session -d -s agent -c /workspace

exec sleep infinity