FROM ubuntu:22.04

# Éviter les prompts interactifs
ENV DEBIAN_FRONTEND=noninteractive
ENV container=docker

# Installation des dépendances de base
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    systemd \
    systemd-sysv \
    git \
    bash-completion \
    iproute2 \
    iptables \
    ipset \
    ipvsadm \
    socat \
    conntrack \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Copier le script systemctl customisé
COPY ./systemctl /usr/local/bin/systemctl-fake
RUN chmod +x /usr/local/bin/systemctl-fake

# Configurer les clés GPG et repos pour Kubernetes 1.32
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

# Installer containerd
RUN apt-get update && apt-get install -y containerd \
    && mkdir -p /etc/containerd \
    && containerd config default > /etc/containerd/config.toml \
    && sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml \
    && rm -rf /var/lib/apt/lists/*

# Lien attendu par certains outils (kubeadm, crictl, scripts legacy)
RUN mkdir -p /var/run/containerd \
    && ln -sf /run/containerd/containerd.sock /var/run/containerd/containerd.sock

# Installer crictl (CLI CRI pour containerd)
RUN CRICTL_VERSION="v1.32.0" \
    && curl -L https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz \
    | tar -xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/crictl

# Configurer crictl pour containerd
RUN cat <<EOF >/etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# Installer Kubernetes 1.32.4
RUN apt-get update && apt-get install -y \
    kubectl=1.32.4-1.1 \
    kubeadm=1.32.4-1.1 \
    kubelet=1.32.4-1.1 \
    && apt-mark hold kubelet kubeadm kubectl \
    && rm -rf /var/lib/apt/lists/*

# Télécharger docker-compose standalone (pour compatibilité)
RUN curl -Lf -o /usr/bin/docker-compose https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m) \
    && chmod +x /usr/bin/docker-compose

# Configurer systemd pour conteneur
RUN systemctl set-default multi-user.target \
    && systemctl mask systemd-remount-fs.service \
    && systemctl mask sys-kernel-config.mount \
    && systemctl mask sys-kernel-debug.mount \
    && systemctl mask sys-fs-fuse-connections.mount

# Configurer les modules kernel nécessaires
RUN echo "overlay" >> /etc/modules-load.d/containerd.conf \
    && echo "br_netfilter" >> /etc/modules-load.d/containerd.conf

# Configurer sysctl pour Kubernetes
RUN echo "net.bridge.bridge-nf-call-iptables  = 1" >> /etc/sysctl.d/99-kubernetes-cri.conf \
    && echo "net.ipv4.ip_forward                 = 1" >> /etc/sysctl.d/99-kubernetes-cri.conf \
    && echo "net.bridge.bridge-nf-call-ip6tables = 1" >> /etc/sysctl.d/99-kubernetes-cri.conf

# Volume pour kubelet
VOLUME ["/var/lib/kubelet"]

# Copier les fichiers de configuration
COPY ./kubelet.service /etc/systemd/system/kubelet.service
COPY ./kubelet.env /etc/systemd/system/kubelet.env
COPY ./wrapkubeadm.sh /usr/local/bin/kubeadm
COPY ./tokens.csv /etc/pki/tokens.csv
COPY ./resolv.conf.override /etc/resolv.conf.override
COPY ./deploy-k8s.sh /etc/kubernetes/deploy-k8s.sh

# Rendre les scripts exécutables
RUN chmod +x /etc/kubernetes/deploy-k8s.sh /usr/local/bin/kubeadm

# Configuration du MOTD et du prompt
COPY ./motd /etc/motd
RUN echo 'cat /etc/motd' >> /root/.bashrc \
    && echo 'export PS1="[\h \W]$ "' >> /root/.bashrc

# Configuration kubectl
RUN mkdir -p /root/.kube \
    && ln -sf /etc/kubernetes/admin.conf /root/.kube/config \
    && rm -f /etc/machine-id

# Activer l'autocomplétion kubectl
RUN kubectl completion bash > /etc/bash_completion.d/kubectl \
    && echo 'source <(kubectl completion bash)' >> /root/.bashrc

# Créer le répertoire pour les tokens
RUN mkdir -p /etc/pki

WORKDIR /root

# Point d'entrée
CMD export PATH="/usr/local/bin:$PATH" && \
    ln -sf /usr/local/bin/systemctl-fake /usr/bin/systemctl && \
    mount --make-shared / && \
    modprobe overlay 2>/dev/null || true && \
    modprobe br_netfilter 2>/dev/null || true && \
    sysctl --system && \
    systemctl start containerd && \
    systemctl start kubelet && \
    /bin/bash /etc/kubernetes/deploy-k8s.sh && \
    while true; do bash -l; done

