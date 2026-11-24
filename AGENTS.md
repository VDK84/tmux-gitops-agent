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
* **Agents d'IA:**
  * `gemini` / `agy` (Gemini CLI / Antigravity CLI oficial de Google)
  * `pi` (`@mariozechner/pi-coding-agent`)
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
