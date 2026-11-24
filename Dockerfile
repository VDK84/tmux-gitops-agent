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
RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
    -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl \
    && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" | tar -xz \
    && mv linux-${TARGETARCH}/helm /usr/local/bin/helm && rm -rf linux-${TARGETARCH} \
    && curl -fsSL "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${TARGETARCH}" \
    -o /usr/local/bin/argocd && chmod +x /usr/local/bin/argocd \
    && curl -fsSL "https://dl.gitea.com/tea/${TEA_VERSION}/tea-${TEA_VERSION}-linux-${TARGETARCH}" \
    -o /usr/local/bin/tea && chmod +x /usr/local/bin/tea \
    && curl -fsSL "https://github.com/openbao/openbao/releases/download/v${OPENBAO_VERSION}/bao_${OPENBAO_VERSION}_Linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin bao && chmod +x /usr/local/bin/bao \
    && curl -fsSL "https://dl.smallstep.com/gh-release/cli/gh-release-header/v${STEP_CLI_VERSION}/step_linux_${STEP_CLI_VERSION}_${TARGETARCH}.tar.gz" \
    | tar -xz --strip-components=2 -C /usr/local/bin "step_${STEP_CLI_VERSION}/bin/step" && chmod +x /usr/local/bin/step \
    && curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    | tar -xz -C /usr/local/bin gitleaks && chmod +x /usr/local/bin/gitleaks \
    && curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${TARGETARCH}" \
    -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# 4. Agents IA: Gemini CLI (@google/gemini-cli) + pi.dev CLI (@mariozechner/pi-coding-agent)
RUN npm install -g @google/gemini-cli @mariozechner/pi-coding-agent \
    && ln -s $(which gemini) /usr/local/bin/agy 2>/dev/null || true

# 5. Configuració tmux i auto-attach en entrar per SSH interactiu
RUN printf 'set -g mouse on\nset -g history-limit 50000\nset -g base-index 1\nset -g default-terminal "screen-256color"\n' > /root/.tmux.conf \
    && printf 'alias sync-clean="for d in /workspace/*/.git; do repo=\$(dirname \$d); echo \"==> Netejant \$repo\"; git -C \$repo fetch origin && git -C \$repo checkout main && git -C \$repo reset --hard origin/main && git -C \$repo clean -fd; done"\nalias agy="gemini"\n' >> /root/.bashrc \
    && printf '\n# Auto-enganxar a la sessió tmux en entrar per SSH interactiu\nif [[ -n "$SSH_CONNECTION" ]] && [[ -z "$TMUX" ]] && [[ $- == *i* ]]; then\n  exec tmux new-session -A -s agent\nfi\n' >> /root/.bashrc

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
