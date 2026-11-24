# 🤖 Agent Workspace (`agent-workspace`)

Entorn de treball efímer i autònom per a agents d'IA (`pi.dev`) corrent dins del clúster **K3s**, amb sessió persistent de `tmux`, caixa d'eines completa de DevOps/xarxa i integració directa amb **Forgejo** i **Kubernetes** via RBAC.

---

## 🏗️ Arquitectura i Filosofia

* **Stateless / Sense PVC:** El contenidor no utilitza volums persistents (Longhorn). Qualsevol estat o memòria a llarg termini es guarda directament als repositoris de Git (ex. `infra/agent-memory`), garantint arrencades netes i zero bloquejos de volums RWO en cas de reinici o migració de node.
* **Identitat Aïllada (Compte Bot):** L'agent opera amb un usuari dedicat de Forgejo (`pi-agent`), separant les seves Pull Requests i *commits* de la sessió personal de l'administrador.
* **Flux GitOps Estricte:** L'agent treballa sobre branques `feature/*` a **Forgejo** (font de desenvolupament amb accés *WRITE*) i obre Pull Requests per a revisió humana abans de fusionar a `main` (que es replica a GitHub en mode *READ-only* per a ArgoCD).
* **Autenticació K3s Nativa:** Utilitza un `ServiceAccount` amb permisos RBAC dins el clúster, eliminant la necessitat de gestionar fitxers `kubeconfig` externs.

---

## 📂 Estructura del Repositori

```text
.
├── .forgejo/
│   └── workflows/
│       └── build-image.yaml    # CI/CD: càlcul SemVer, etiquetatge Git i construcció de la imatge
├── Dockerfile                  # Imatge Debian Slim + Node 22 + eines K8s, xarxa, SSH, crypto i pi.dev
├── entrypoint.sh               # Script d'inicialització: CA interna, SSH, Git/tea, repos i tmux
└── readme.md                   # Documentació del repositori
```

---

## 🧰 Eines Incloses a la Imatge

| Categoria | Eines |
| --- | --- |
| **Agent & Terminal** | `pi` (`@mariozechner/pi-coding-agent`), `tmux`, `less`, `vim-tiny`, `nano`, `tree`, `procps` |
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
| `FORGEJO_BOT_TOKEN` | Token d'accés de l'usuari bot a Forgejo (configura `git` i `tea`). | *(Requerida)* |
| `FORGEJO_URL` | URL base de la instància de Forgejo. | `https://git.rusc.local` |
| `GIT_BOT_NAME` | Nom d'usuari per als commits de Git. | `pi-agent` |
| `GIT_BOT_EMAIL` | Correu electrònic per als commits de Git. | `pi-agent@rusc.local` |
| `WORKSPACE_REPOS` | Llista de repositoris separats per espais a clonar dins `/workspace`. | `argocd-bootstrap infra docker-server` |

*(Nota: Si es munta el certificat arrel de `step-ca` a `/usr/local/share/ca-certificates/`, l'entrypoint executa `update-ca-certificates` automàticament).*

---

## 🚀 Ús Diari

### Connectar-se a la sessió `tmux` del Pod

Des de qualsevol màquina amb `kubectl` configurat:

```bash
kubectl exec -it -n ai deploy/agent-workspace -- tmux attach -t agent
```

### Comandes i Àlies Ràpids dins el Contenidor

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

## 🏷️ Versionat Semàntic Automàtic (SemVer) & CI/CD

El workflow de Forgejo Actions ([.forgejo/workflows/build-image.yaml](.forgejo/workflows/build-image.yaml)) s'encarrega automàticament del cicle complet de versions SemVer i de la construcció de la imatge quan es fa un `push` a la branca `main`:

### 1. Detecció d'etiquetes i càlcul de versió
- Analitza les etiquetes Git remotes existents (`vX.Y.Z`). Si no n'hi ha cap, la versió inicial base arrenca a `v0.1.0`.
- Avalua els missatges dels commits des de l'última etiqueta segons l'estàndard **Conventional Commits**:
  - `BREAKING CHANGE:` o prefix `!` (ex: `feat!:`, `fix!:`) o clau `#major` ➔ **Increment MAJOR** (`v1.0.0` ➔ `v2.0.0`).
  - Prefix `feat:` o `feat(...)` o clau `#minor` ➔ **Increment MINOR** (`v0.1.0` ➔ `v0.2.0`).
  - Prefixos `fix:`, `chore:`, `ci:`, `docs:`, `refactor:`, etc. (o clau `#patch`) ➔ **Increment PATCH** (`v0.1.0` ➔ `v0.1.1`).

### 2. Creació d'etiqueta Git i Release a Forgejo
- Crea el tag anotat Git (`vX.Y.Z`) i el puja automàticament al repositori Forgejo amb el bot de CI (`[skip ci]`).
- Crea automàticament una **Release** a Forgejo amb el resum del registre de canvis (changelog) associat a la versió.

### 3. Publicació al Forgejo Container Registry
Construeix la imatge Docker injectant l'argument `APP_VERSION=${NEW_VERSION}` i publica les següents etiquetes al registre intern:
* `git.rusc.local/vdk84/agent-workspace:latest`
* `git.rusc.local/vdk84/agent-workspace:vX.Y.Z` (ex: `v0.1.0`)
* `git.rusc.local/vdk84/agent-workspace:X.Y.Z` (ex: `0.1.0`)
* `git.rusc.local/vdk84/agent-workspace:vX.Y` (ex: `v0.1`)
* `git.rusc.local/vdk84/agent-workspace:vX` (ex: `v0`)
* `git.rusc.local/vdk84/agent-workspace:<commit-sha>`

### 4. Llançament manual (`workflow_dispatch`)
També es pot activar el workflow manualment des de Forgejo Actions, escollint el tipus d'increment desitjat (`auto`, `patch`, `minor` o `major`).

Per reiniciar el deployment de K3s un cop publicada la nova imatge:

```bash
kubectl rollout restart deployment/agent-workspace -n ai
```
