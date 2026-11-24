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

# 1. Paquets base del sistema, xarxa, SSH, crypto i cerca ràpida
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Terminal, editors i utilitats de procés
    tmux less procps tree vim-tiny nano file unzip zip tar xz-utils \
    # Xarxa i diagnòstic (DNS, sockets, rutes, paquets)
    openssh-client curl wget ca-certificates \
    dnsutils iputils-ping netcat-openbsd iproute2 traceroute tcpdump \
    # Seguretat, generació de contrasenyes i xifrat
    openssl pwgen age gnupg \
    # Git, cerca ultraràpida (per a l'agent) i manipulació de text
    git ripgrep fd-find jq gettext-base make \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s $(which fdfind) /usr/local/bin/fd

# 2. kubectl
RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
    -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

# 3. helm
RUN curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" | tar -xz \
    && mv linux-${TARGETARCH}/helm /usr/local/bin/helm \
    && rm -rf linux-${TARGETARCH}

# 4. argocd CLI
RUN curl -fsSL "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${TARGETARCH}" \
    -o /usr/local/bin/argocd && chmod +x /usr/local/bin/argocd

# 5. tea (Forgejo / Gitea CLI oficial)
RUN curl -fsSL "https://dl.gitea.com/tea/${TEA_VERSION}/tea-${TEA_VERSION}-linux-${TARGETARCH}" \
    -o /usr/local/bin/tea && chmod +x /usr/local/bin/tea

# 6. OpenBao CLI (bao)
RUN curl -fsSL "https://github.com/openbao/openbao/releases/download/v${OPENBAO_VERSION}/bao_${OPENBAO_VERSION}_Linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin bao && chmod +x /usr/local/bin/bao

# 7. step CLI (per interactuar amb el teu step-ca intern)
RUN curl -fsSL "https://dl.smallstep.com/gh-release/cli/gh-release-header/v${STEP_CLI_VERSION}/step_linux_${STEP_CLI_VERSION}_${TARGETARCH}.tar.gz" \
    | tar -xz --strip-components=2 -C /usr/local/bin "step_${STEP_CLI_VERSION}/bin/step" \
    && chmod +x /usr/local/bin/step

# 8. gitleaks (pre-commit hook anti-leaks)
RUN curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    | tar -xz -C /usr/local/bin gitleaks && chmod +x /usr/local/bin/gitleaks

# 9. yq (parseig/edició YAML)
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${TARGETARCH}" \
    -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# 10. pi.dev coding agent CLI
RUN npm install -g @mariozechner/pi-coding-agent

# Configuració de tmux (scroll tàctil per mòbil, historial ampli i colors 256)
RUN printf 'set -g mouse on\nset -g history-limit 50000\nset -g base-index 1\nset -g default-terminal "screen-256color"\n' > /root/.tmux.conf

# Alias útils per netejar i sincronitzar tots els repos de cop
RUN printf 'alias sync-clean="for d in /workspace/*/.git; do repo=\$(dirname \$d); echo \"==> Netejant \$repo\"; git -C \$repo fetch origin && git -C \$repo checkout main && git -C \$repo reset --hard origin/main && git -C \$repo clean -fd; done"\n' >> /root/.bashrc

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]