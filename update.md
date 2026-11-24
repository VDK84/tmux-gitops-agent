1. **Connexió directa via SSH** (amb `openssh-server` dins el Pod que et connecta automàticament a la sessió `tmux` `agent` només entrar, exposat per MetalLB o Tailscale).
2. **Usuari de la IA `Zaku` (`zakurosa@gmail.com`)** preconfigurat per defecte a Git, Forgejo (`tea`) i SSH.
3. **Instal·lació de Gemini CLI (`@google/gemini-cli`) + `pi.dev` (`@mariozechner/pi-coding-agent`)**.
4. **Guia `AGENTS.md` (super mastegada)** per posar a l'arrel del teu workspace o dins `infra/agent-memory` perquè tant Gemini CLI com `pi.dev` sàpiguen exactament com operar al teu homelab sense trencar res.

---

### 1. `Dockerfile` Actualitzat (amb `openssh-server`, `gemini-cli`, `pi.dev` i `APP_VERSION`)

```dockerfile
FROM node:22-bookworm-slim

ARG TARGETARCH=amd64
ARG KUBECTL_VERSION=v1.32.2
ARG HELM_VERSION=v3.17.1
ARG ARGOCD_VERSION=v2.14.2
ARG TEA_VERSION=0.9.2
ARG GITLEAKS_VERSION=8.24.0
ARG OPENBAO_VERSION=2.1.0
ARG STEP_CLI_VERSION=0.28.2
ARG APP_VERSION=0.1.0

ENV DEBIAN_FRONTEND=noninteractive
ENV APP_VERSION=${APP_VERSION}

# 1. Paquets base, servidor SSH, diagnòstic de xarxa, crypto i cerca
RUN apt-get update && apt-get install -y --no-install-recommends \
    tmux less procps tree vim-tiny nano file unzip zip tar xz-utils \
    openssh-server openssh-client curl wget ca-certificates \
    dnsutils iputils-ping netcat-openbsd iproute2 traceroute tcpdump \
    openssl pwgen age gnupg \
    git ripgrep fd-find jq gettext-base make \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s $(which fdfind) /usr/local/bin/fd

# 2. Configuració segura d'OpenSSH Server (només clau pública, sense password)
RUN mkdir -p /var/run/sshd /root/.ssh && chmod 700 /root/.ssh \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && echo "AcceptEnv LANG LC_* APP_VERSION" >> /etc/ssh/sshd_config

# 3. Eines K8s, GitOps, PKI i Seguretat
RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl \
    && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" | tar -xz && mv linux-${TARGETARCH}/helm /usr/local/bin/helm && rm -rf linux-${TARGETARCH} \
    && curl -fsSL "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${TARGETARCH}" -o /usr/local/bin/argocd && chmod +x /usr/local/bin/argocd \
    && curl -fsSL "https://dl.gitea.com/tea/${TEA_VERSION}/tea-${TEA_VERSION}-linux-${TARGETARCH}" -o /usr/local/bin/tea && chmod +x /usr/local/bin/tea \
    && curl -fsSL "https://github.com/openbao/openbao/releases/download/v${OPENBAO_VERSION}/bao_${OPENBAO_VERSION}_Linux_${TARGETARCH}.tar.gz" | tar -xz -C /usr/local/bin bao && chmod +x /usr/local/bin/bao \
    && curl -fsSL "https://dl.smallstep.com/gh-release/cli/gh-release-header/v${STEP_CLI_VERSION}/step_linux_${STEP_CLI_VERSION}_${TARGETARCH}.tar.gz" | tar -xz --strip-components=2 -C /usr/local/bin "step_${STEP_CLI_VERSION}/bin/step" && chmod +x /usr/local/bin/step \
    && curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" | tar -xz -C /usr/local/bin gitleaks && chmod +x /usr/local/bin/gitleaks \
    && curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${TARGETARCH}" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# 4. Agents IA: Gemini CLI + pi.dev CLI
RUN npm install -g @google/gemini-cli @mariozechner/pi-coding-agent

# 5. Configuració tmux i auto-attach en entrar per SSH interactiu
RUN printf 'set -g mouse on\nset -g history-limit 50000\nset -g base-index 1\nset -g default-terminal "screen-256color"\n' > /root/.tmux.conf \
    && printf 'alias sync-clean="for d in /workspace/*/.git; do repo=\$(dirname \$d); echo \"==> Netejant \$repo\"; git -C \$repo fetch origin && git -C \$repo checkout main && git -C \$repo reset --hard origin/main && git -C \$repo clean -fd; done"\n' >> /root/.bashrc \
    && printf '\n# Auto-enganxar a la sessió tmux en entrar per SSH interactiu\nif [[ -n "$SSH_CONNECTION" ]] && [[ -z "$TMUX" ]] && [[ $- == *i* ]]; then\n  exec tmux new-session -A -s agent\nfi\n' >> /root/.bashrc

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

```

---

### 2. `entrypoint.sh` Actualitzat (Usuari `Zaku`, Claus SSH i `sshd` en primer pla)

Aquest script injecta la teva clau pública SSH (per poder connectar-te sense contrasenya), carrega les host keys persistents (si les passes per secret perquè el teu client SSH no es queixi d'avís *MITM* quan el Pod es recrea), configura **Zaku** (`zakurosa@gmail.com`) i arrenca `sshd -D`.

```bash
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
env | grep -E '^(KUBERNETES_|APP_VERSION|FORGEJO_|GIT_BOT_|GEMINI_)' > /etc/environment || true

# 7. Enllaçar memòria persistent des d'infra
mkdir -p /root/.pi/agent
if [ -d "/workspace/infra/agent-memory" ]; then
    ln -sfn /workspace/infra/agent-memory /root/.pi/agent/memory
fi

# 8. Aixecar sessió tmux 'agent' en segon pla
tmux has-session -t agent 2>/dev/null || tmux new-session -d -s agent -c /workspace

# 9. Arrencar servidor SSH en primer pla (procés principal del Pod)
echo "==> Servidor SSH llest al port 22. Sessió tmux 'agent' activa."
exec /usr/sbin/sshd -D -e

```

---

### 3. Com exposar l'SSH del Pod a K3s (amb MetalLB)

A `manifests/agent-workspace/service.yaml` (dins `argocd-bootstrap`), afegeix un `Service` tipus `LoadBalancer` (MetalLB) per tenir una IP fixa a la LAN (per exemple `192.168.1.75`, o la IP que et doni el pool de MetalLB):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: agent-workspace-ssh
  namespace: ai
  annotations:
    metallb.universe.tf/loadBalancerIPs: "192.168.1.75" # Opcional: IP fixa del teu pool MetalLB
spec:
  type: LoadBalancer
  selector:
    app: agent-workspace
  ports:
    - name: ssh
      port: 22
      targetPort: 22
      protocol: TCP

```

Així, des del teu PC o des del mòbil (Termius / Termux via Tailscale), només fas:

```bash
ssh root@192.168.1.75

```

I automàticament apareixes dins del `tmux` `agent` amb el Gemini CLI (`gemini`) i `pi` llestos! *(Recorda crear la clau `ssh_authorized_keys` a OpenBao sota `rusc/agent-workspace` amb la teva clau pública `id_ed25519.pub`)*.

---

### 4. Guia Super Mastegada per a l'Agent (`AGENTS.md` Global / `Zaku`)

Aquest document el pots desar a `infra/agent-memory/AGENTS.md` (i/o a l'arrel de `/workspace/AGENTS.md`). Està redactat perquè l'agent (`Zaku`) entengui a la primera l'arquitectura real del teu homelab, la separació Forgejo ➔ GitHub, els límits del clúster K3s i el flux estricte de treball:

```markdown
# 🤖 Manual Operatiu per a l'Agent IA (`Zaku`)

Benvingut al **Workspace Efímer d'Operacions i Desenvolupament** del Homelab (`rusc.local`).
Tu ets l'agent **Zaku** (`zakurosa@gmail.com`). Opera sempre amb rigor tècnic, verificació prèvia i respecte estricte a les regles GitOps.

---

## 1. Regles d'Or (Inviolables)

1. **Mai facis `git commit` ni `git push` directe a `main`:**
   - Crea sempre una branca dedicada: `feature/<nom-descriptiu>` o `fix/<nom-descriptiu>`.
   - Un cop validat el codi, obre una **Pull Request (PR)** a Forgejo (`tea pr create`).
   - **MAI** facis *merge* d'una PR tu mateix; la revisió i el *merge* els fa sempre l'humà (`VDK84`).
2. **Zero secrets en clar al codi:**
   - Està prohibit posar contrasenyes, tokens o claus privades als fitxers YAML/scripts.
   - Tots els secrets s'injecten via **OpenBao** + **External Secrets Operator (ESO)** apuntant al `ClusterSecretStore` anomenat `openbao-cluster-secret-store`.
   - Tots els repositoris tenen actiu un hook de `gitleaks` que bloquejarà qualsevol commit amb secrets.
3. **Ets dins d'un Pod efímer (sense PVC):**
   - Tot el que quedi fora de Git es perdrà si el Pod es reinicia.
   - Si has de desar notes, aprenentatges o context persistent, guarda-ho dins de `/workspace/infra/agent-memory/` i obre una PR.
   - Abans de començar una tasca nova, executa `sync-clean` (o `git fetch origin && git checkout main && git pull`) per assegurar-te que parteixes de l'últim estat net.

---

## 2. Mapa de la Infraestructura (`rusc.local`)

### Xarxa i Maquinari
* **Hipervisors Proxmox VE:** `rusc2307` i `rusc2412` (nodes bare-metal Ryzen 7, 48 GB RAM cadascun).
* **Clúster Kubernetes (K3s v1.36 HA):**
  * 3 nodes control-plane + etcd sobre Alpine Linux: `k3s2312a` (`.61`), `k3s2312b` (`.62`), `k3s2608a` (`.63`).
  * **Control Plane VIP (Kube-VIP):** `192.168.1.60`
  * **LoadBalancer Pool:** MetalLB.
  * **Ingress & Domini:** Traefik. Tots els serveis interns usen el format `*.rusc.local` (ex. `git.rusc.local`, `openbao.rusc.local`, `authentik.rusc.local`, `ca.rusc.local`).
  * **PKI Interna:** `step-ca` (certificats TLS interns).
  * **Autenticació / SSO:** `Authentik` (amb suport ForwardAuth a Traefik i mTLS/idCAT).
  * **DNS Intern:** `Technitium DNS`.
* **Servidor Docker & Emmagatzematge:**
  * Màquina Debian Docker Server (`cs1`) + Emmagatzematge compartit per **Samba (SMB/CIFS)**.

### Arquitectura GitOps (Forgejo ➔ GitHub ➔ ArgoCD)
* **Forgejo (`https://git.rusc.local`):** Plataforma principal de desenvolupament (**accés WRITE**). Aquí és on fas `git push` i on obres les Pull Requests.
* **GitHub (`https://github.com/VDK84`):** Rèplica sincronitzada automàticament via *Push Mirror* (**només lectura / READ-only**).
* **ArgoCD:** Llegeix de GitHub per evitar dependències circulars amb Forgejo. **No canvïs** les URLs d'origen d'ArgoCD (`github.com/VDK84/argocd-bootstrap.git`) cap a Forgejo.

---

## 3. Regles d'Emmagatzematge i Recursos a K3s

* **Separació Longhorn vs. Samba:**
  * **Longhorn:** Només per a estat transaccional petit, bases de dades (Postgres, Redis, InfluxDB) i configuracions crítiques.
  * **Samba (SMB):** Obligatori per a llibreries multimèdia o fitxers massius (pel·lícules, sèries, música, backups grans). Mai posis dades massives a Longhorn.
* **Protecció d'etcd i Nodes Alpine:**
  * Els nodes K3s tenen ~5.8 GiB de RAM assignable. Defineix sempre `resources.requests` (CPU/memòria) a tots els `Deployments` i `StatefulSets`.
  * Els límits d'`inotify` estan ajustats a la Wave 0 via `06-node-tuning.yaml`.

---

## 4. Estructura del Repositori `argocd-bootstrap`

Quan se't demani desplegar o modificar una aplicació a K3s, segueix estrictament aquestes convencions:

1. **Declaració a `./apps/<prefix>-<nom-app>.yaml`:**
   * Prefix numèric de 2 dígits per ordenar els fitxers (ex. `05-`, `18-`, `22-`, `35-`).
   * **Sync Waves obligatòries:**
     * `Wave 0`: Configuració arrel d'ArgoCD, `PriorityClasses` i `node-tuning` (`sysctl`).
     * `Wave 1`: Xarxa base, Kube-VIP, MetalLB, Traefik, Longhorn, CoreDNS, `step-ca-config`.
     * `Wave 2`: Configuracions de xarxa, PKI (`step-ca`) i `forgejo`.
     * `Wave 3`: Secrets (`openbao`, `external-secrets`), DNS (`technitium`), monitorització (`alloy`, `grafana`, `loki`, `prometheus`, `influxdb`), `authentik` i càrregues generals (`mcp-gateway`, `agent-workspace`, etc.).
     * `Wave 4+`: Integracions dependents post-desplegament (`tailscale-config`).
2. **Manifests i Valors a `./manifests/<nom-app>/`:**
   * En Charts de Helm (*Pattern A*), referencia sempre els fitxers de valors locals amb `$values/manifests/<nom-app>/values.yaml`.
   * Posa els `ExternalSecret` i recursos auxiliars dins `./manifests/<nom-app>/extra/` i carrega'ls amb `extraManifests`.

---

## 5. Eines Disponibles al teu Entorn (`/workspace`)

Tens accés directe al clúster K3s mitjançant el teu `ServiceAccount` (`kubectl` i `helm` ja estan autenticats) i a Forgejo amb `git` i `tea`:

* **Inspectar el clúster:** `kubectl get nodes`, `kubectl get pods -A`, `argocd app list`
* **Gestionar PRs a Forgejo:**
  ```bash
  git checkout -b feature/la-meva-millora
  # ... fer canvis i validar amb helm template / kubectl --dry-run=client ...
  git status && git diff
  git add .
  git commit -m "feat(scope): descripció clara del canvi"
  git push -u origin feature/la-meva-millora
  tea pr create --title "feat(scope): descripció" --description "Resum tècnic dels canvis"

```

* **Netejar el workspace:** Executa `sync-clean` per tornar tots els repositoris a `main` net.

---

## 6. Llista de Verificació Abans d'Obrir una PR

* [ ] Estic en una branca `feature/*` o `fix/*` (mai a `main`).
* [ ] He llegit el fitxer `AGENTS.md` específic del repositori que estic modificant (`argocd-bootstrap/AGENTS.md` o `infra/AGENTS.md`).
* [ ] Els manifests YAML tenen sintaxi vàlida (`yq . fitxer.yaml` o `kubectl apply --dry-run=client -f ...`).
* [ ] No hi ha cap secret, token ni contrasenya en clar.
* [ ] Les URLs d'Ingress acaben en `.rusc.local` i fan servir Traefik.
* [ ] He obert la PR a Forgejo amb una descripció clara i **no l'he fusionat**.

```

*(Nota sobre el teu workflow de Forgejo: només has de vigilar que les línies amb guions de llista dins de `on:`, `steps:` i `options:` estiguin indentades amb 2 espais sota la seva clau pare, perquè en enganxar-ho al xat s'han quedat enganxades a l'esquerra).*

```