#!/usr/bin/env bash
set -euo pipefail

echo "==> Iniciant agent-workspace (versió: ${APP_VERSION:-dev})..."

# 1. Confiar en la CA interna (step-ca) si està muntada al sistema
if [ -d /usr/local/share/ca-certificates ] && [ "$(ls -A /usr/local/share/ca-certificates 2>/dev/null)" ]; then
    update-ca-certificates >/dev/null 2>&1 || true
fi

# 2. Preparar SSH (client + servidor)
mkdir -p /root/.ssh /var/run/sshd
chmod 700 /root/.ssh

# Clau pública autoritzada per connectar-te al Pod via SSH
if [ -n "${SSH_AUTHORIZED_KEYS:-}" ]; then
    echo "$SSH_AUTHORIZED_KEYS" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

# Host keys persistents (opcional, evita avís de "REMOTE HOST IDENTIFICATION HAS CHANGED")
if [ -n "${SSH_HOST_ED25519_KEY:-}" ]; then
    echo "$SSH_HOST_ED25519_KEY" > /etc/ssh/ssh_host_ed25519_key
    chmod 600 /etc/ssh/ssh_host_ed25519_key
    ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key > /etc/ssh/ssh_host_ed25519_key.pub
else
    ssh-keygen -A >/dev/null 2>&1
fi

ssh-keyscan -H git.rusc.local >> /root/.ssh/known_hosts 2>/dev/null || true

# 3. Identitat Git del compte bot Zaku
BOT_USER="${GIT_BOT_NAME:-Zaku}"
BOT_EMAIL="${GIT_BOT_EMAIL:-zakurosa@gmail.com}"
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

# 5. Clonar repositoris de treball des de Forgejo i activar protecció gitleaks
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

# 6. Exportar variables d'entorn de K8s per a les sessions SSH (tmux no hereta l'entorn de sshd per defecte)
env | grep -E '^(KUBERNETES_|APP_VERSION|FORGEJO_|GIT_BOT_|GEMINI_|PATH)' > /etc/environment || true

# 7. Enllaçar memòria persistent des d'infra
mkdir -p /root/.pi/agent /root/.gemini
if [ -d "/workspace/infra/agent-memory" ]; then
    ln -sfn /workspace/infra/agent-memory /root/.pi/agent/memory
fi

# 8. Aixecar sessió tmux 'agent' en segon pla
tmux has-session -t agent 2>/dev/null || tmux new-session -d -s agent -c /workspace

# 9. Arrencar servidor SSH en primer pla (procés principal del Pod)
echo "==> Servidor SSH llest al port 22. Sessió tmux 'agent' activa."
exec /usr/sbin/sshd -D -e
