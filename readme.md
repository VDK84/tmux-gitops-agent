# 🤖 Agent Workspace (`agent-workspace`)

Entorn de treball efímer i autònom per a agents d'IA (**Gemini CLI / `agy`** i **`pi.dev`**) corrent dins del clúster **K3s**, amb accés directe via **SSH**, sessió persistent de **tmux**, caixa d'eines completa de DevOps/xarxa i integració directa amb **Forgejo** i **Kubernetes** via RBAC.

L'agent opera sota la identitat de **Zaku** (`zakurosa@gmail.com`).

---

## 🏗️ Arquitectura i Filosofia

* **Connexió Nativa via SSH:** Disposa d'un servidor `openssh-server` configurat de forma segura (només autenticació per clau pública). En entrar per SSH, s'auto-enganxa automàticament a la sessió persistent `tmux` anomenada `agent`.
* **Doble Motor d'IA:** Inclou tant **Gemini CLI** (`gemini` / `agy` via `@google/gemini-cli`) com **pi.dev** (`pi` via `@mariozechner/pi-coding-agent`), llestos per operar sobre el codi.
* **Stateless / Sense PVC:** El contenidor no utilitza volums persistents (Longhorn). Qualsevol estat o memòria a llarg termini es guarda directament als repositoris de Git (ex. `infra/agent-memory`), garantint arrencades netes i zero bloquejos de volums RWO en cas de reinici o migració de node.
* **Identitat Aïllada (Compte Bot `Zaku`):** L'agent opera amb un usuari dedicat de Forgejo (`Zaku`, `zakurosa@gmail.com`), separant les seves Pull Requests i *commits* de la sessió personal de l'administrador (`VDK84`).
* **Flux GitOps Estricte:** L'agent treballa sobre branques `feature/*` a **Forgejo** (font de desenvolupament amb accés *WRITE*) i obre Pull Requests per a revisió humana abans de fusionar a `main` (que es replica a GitHub en mode *READ-only* per a ArgoCD). Consulta el manual complet a [AGENTS.md](AGENTS.md).
* **Autenticació K3s Nativa:** Utilitza un `ServiceAccount` amb permisos RBAC dins el clúster, eliminant la necessitat de gestionar fitxers `kubeconfig` externs.

---

## 📂 Estructura del Repositori

```text
.
├── .forgejo/
│   └── workflows/
│       └── build-image.yaml    # CI/CD: càlcul SemVer, etiquetatge Git i construcció de la imatge
├── AGENTS.md                   # Manual d'instruccions operatives per a l'agent Zaku
├── Dockerfile                  # Imatge Debian Slim + Node 22 + SSH + Gemini CLI + pi.dev + eines DevOps
├── entrypoint.sh               # Inicialització: SSH server, step-ca, Git/tea (Zaku), repos i tmux
└── readme.md                   # Documentació del repositori
```

---

## 🧰 Eines Incloses a la Imatge

| Categoria | Eines |
| --- | --- |
| **Agents d'IA & Terminal** | `gemini` / `agy` (`@google/gemini-cli`), `pi` (`@mariozechner/pi-coding-agent`), `tmux`, `openssh-server`, `less`, `vim-tiny`, `nano`, `tree`, `procps` |
| **Kubernetes & GitOps** | `kubectl`, `helm`, `argocd` CLI, `yq` |
| **Git & Forgejo** | `git`, `tea` (Forgejo/Gitea CLI), `gitleaks` (pre-commit hook anti-leaks) |
| **Seguretat & PKI** | `bao` (OpenBao CLI), `step` (Smallstep CA CLI), `openssl`, `age`, `pwgen`, `gnupg` |
| **Xarxa & Diagnòstic** | `openssh-client` (`ssh`, `ssh-keygen`, `ssh-keyscan`), `curl`, `wget`, `dig` (`dnsutils`), `ping`, `nc`, `ip`, `traceroute`, `tcpdump` |
| **Cerca & Parseig** | `ripgrep` (`rg`), `fd` (`fd-find`), `jq`, `envsubst` (`gettext-base`) |

---

## ⚙️ Variables d'Entorn (`entrypoint.sh`)

En arrencar, l'`entrypoint.sh` configura automàticament l'entorn a partir de les variables injectades al Pod (via OpenBao + `ExternalSecret` en `argocd-bootstrap`):

| Variable | Descripció | Valor per defecte |
| --- | --- | --- |
| `SSH_AUTHORIZED_KEYS` | Clau pública autoritzada (ex: `ssh-ed25519 AAAAC3...`) per connectar-se per SSH. | *(Opcional)* |
| `SSH_HOST_ED25519_KEY` | Clau privada host del servidor SSH (evita avís de MITM en recrear Pods). | *(Opcional)* |
| `FORGEJO_BOT_TOKEN` | Token d'accés de l'usuari bot (`Zaku`) a Forgejo (configura `git` i `tea`). | *(Requerida)* |
| `FORGEJO_URL` | URL base de la instància de Forgejo. | `https://git.rusc.local` |
| `GIT_BOT_NAME` | Nom d'usuari per als commits de Git. | `Zaku` |
| `GIT_BOT_EMAIL` | Correu electrònic per als commits de Git. | `zakurosa@gmail.com` |
| `WORKSPACE_REPOS` | Llista de repositoris separats per espais a clonar dins `/workspace`. | `argocd-bootstrap infra docker-server` |

*(Nota: Si es munta el certificat arrel de `step-ca` a `/usr/local/share/ca-certificates/`, l'entrypoint executa `update-ca-certificates` automàticament).*

---

## 🚀 Accés i Ús Diari

### 1. Connexió via SSH (Mètode recomanat)

Exposant el port 22 del Pod mitjançant un servei `LoadBalancer` (MetalLB) a K3s:

```bash
ssh root@192.168.1.75
```

En entrar per SSH, la sessió s'enganxa automàticament al `tmux` `agent` amb l'entorn i eines llestes.

### 2. Connexió alternativa via `kubectl exec`

```bash
kubectl exec -it -n ai deploy/agent-workspace -- tmux attach -t agent
```

### 3. Comandes i Àlies Ràpids dins el Contenidor

* **Agents d'IA:**
  ```bash
  # Gemini CLI / Antigravity CLI
  gemini
  # o amb l'àlies curt:
  agy

  # pi.dev coding agent
  pi
  ```

* **`sync-clean`:** Recorre tots els repositoris dins `/workspace`, descarta qualsevol canvi local sense *commit*, torna a `main` i sincronitza amb `origin/main`:
  ```bash
  sync-clean
  ```

* **Obrir una Pull Request a Forgejo des de terminal:**
  ```bash
  git checkout -b feature/nom-del-canvi
  # ... canvis i validacions ...
  git commit -am "feat: descripció del canvi"
  git push -u origin feature/nom-del-canvi
  tea pr create --title "feat: descripció" --description "Detalls de la PR"
  ```

---

## 🌐 Exposició del servei SSH a Kubernetes (MetalLB)

A `manifests/agent-workspace/service.yaml` (dins `argocd-bootstrap`), s'exposa el port SSH:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: agent-workspace-ssh
  namespace: ai
  annotations:
    metallb.universe.tf/loadBalancerIPs: "192.168.1.75" # IP fixa del pool de MetalLB
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

---

## 🏷️ Versionat Semàntic Automàtic (SemVer) & CI/CD

El workflow de Forgejo Actions ([.forgejo/workflows/build-image.yaml](.forgejo/workflows/build-image.yaml)) s'encarrega automàticament del cicle complet de versions SemVer i de la construcció de la imatge quan es fa un `push` a la branca `main` o mitjançant `workflow_dispatch`:

### 1. Doble Runner Efímer (Podman Rootless)
Per optimitzar el temps d'execució i garantir màxima fiabilitat eliminant Docker Buildx en entorns rootless, el workflow suporta dos runners:
* **`rusc-runner`** (Per defecte): Imatge tunejada (`git.rusc.local/vdk84/forgejo-runner-image:latest`) amb totes les eines (`podman`, `git`, `curl`, `jq`) i la CA de Smallstep preinstal·lades.
* **`node-slim`** (Fallback / Bootstrap): Imatge oficial `node:22-bookworm-slim` que executa un pas previ de bootstrap per instal·lar les eines necessàries abans del *checkout*.

A les execucions manuals via `workflow_dispatch`, es pot triar el runner desitjat amb el desplegable `runner`.

### 2. Detecció d'etiquetes i càlcul de versió
- Analitza les etiquetes Git remotes existents (`vX.Y.Z`).
- Avalua els missatges dels commits des de l'última etiqueta segons l'estàndard **Conventional Commits**:
  - `BREAKING CHANGE:` o prefix `!` (ex: `feat!:`, `fix!:`) o clau `#major` ➔ **Increment MAJOR** (`v1.0.0` ➔ `v2.0.0`).
  - Prefix `feat:` o `feat(...)` o clau `#minor` ➔ **Increment MINOR** (`v0.1.0` ➔ `v0.2.0`).
  - Prefixos `fix:`, `chore:`, `ci:`, `docs:`, `refactor:`, etc. (o clau `#patch`) ➔ **Increment PATCH** (`v0.1.0` ➔ `v0.1.1`).

### 3. Creació d'etiqueta Git i Release a Forgejo
- Crea el tag anotat Git (`vX.Y.Z`) i el puja automàticament al repositori Forgejo amb el bot de CI (`[skip ci]`).
- Crea automàticament una **Release** a Forgejo amb el resum del registre de canvis (changelog) associat a la versió.

### 4. Publicació al Forgejo Container Registry amb Podman Remote
Construeix la imatge amb `podman --remote` connectat a `unix:///run/user/1000/podman/podman.sock` injectant l'argument `APP_VERSION=${NEW_VERSION}` i publica les següents etiquetes al registre intern:
* `git.rusc.local/vdk84/agent-workspace:latest`
* `git.rusc.local/vdk84/agent-workspace:vX.Y.Z` (ex: `v0.2.0`)
* `git.rusc.local/vdk84/agent-workspace:X.Y.Z` (ex: `0.2.0`)
* `git.rusc.local/vdk84/agent-workspace:vX.Y` (ex: `v0.2`)
* `git.rusc.local/vdk84/agent-workspace:vX` (ex: `v0`)
* `git.rusc.local/vdk84/agent-workspace:<commit-sha>`

### 5. Actualització del Pod a K3s
Per forçar el reinici del deployment amb la nova imatge construïda:

```bash
kubectl rollout restart deployment/agent-workspace -n ai
```
