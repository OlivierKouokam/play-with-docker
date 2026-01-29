#!/bin/bash
# Script de déploiement Kubernetes 1.32 pour Ubuntu 24.04 avec containerd
set -e

echo "################## Installation Kubernetes 1.32 démarrée #####################"

# Détection de l'IP du conteneur
HOST_IP=$(hostname -i | awk '{print $1}')
echo "IP détectée: $HOST_IP"

# Créer /etc/machine-id unique pour chaque instance
if [[ ! -f /etc/machine-id ]]; then
    rm -f /etc/machine-id
    systemd-machine-id-setup
fi

# Attendre que containerd soit prêt
echo "Attente du démarrage de containerd..."
sleep 3

# Vérifier que containerd fonctionne
if ! systemctl is-active --quiet containerd; then
    echo "⚠️  containerd n'est pas actif, tentative de démarrage..."
    systemctl start containerd
    sleep 3
fi

# Attendre que kubelet soit démarré
echo "Attente du démarrage de kubelet..."
sleep 5

# Configuration pour kubeadm init
cat > /tmp/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.32.4
apiServer:
  extraArgs:
    token-auth-file: /etc/pki/tokens.csv
  extraVolumes:
  - name: tokens
    hostPath: /etc/pki/tokens.csv
    mountPath: /etc/pki/tokens.csv
    readOnly: true
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
controlPlaneEndpoint: "$HOST_IP:6443"
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
  kubeletExtraArgs:
    fail-swap-on: "false"
    resolv-conf: /etc/resolv.conf.override
    cgroup-driver: systemd
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
failSwapOn: false
resolvConf: /etc/resolv.conf.override
EOF

# Initialiser le cluster
echo "Initialisation du cluster Kubernetes 1.32..."
kubeadm init \
    --config=/tmp/kubeadm-config.yaml \
    --ignore-preflight-errors=all \
    --skip-phases=addon/kube-proxy

echo "✅ Cluster initialisé"

# Attendre que le cluster soit prêt
echo "Attente que le cluster soit opérationnel..."
sleep 10

# Configurer kubectl pour root
export KUBECONFIG=/etc/kubernetes/admin.conf

# Installer le réseau Flannel (dernière version compatible k8s 1.32)
echo "Installation du réseau Flannel..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Installer kube-proxy manuellement avec les bonnes options
echo "Installation de kube-proxy..."
cat > /tmp/kube-proxy.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-proxy
  namespace: kube-system
data:
  config.conf: |-
    apiVersion: kubeproxy.config.k8s.io/v1alpha1
    kind: KubeProxyConfiguration
    clusterCIDR: "$(ip addr show docker0 | grep -w inet | awk '{ print $2; }')"
    mode: "iptables"
    iptables:
      masqueradeAll: true
    conntrack:
      maxPerCore: 0
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    k8s-app: kube-proxy
  name: kube-proxy
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: kube-proxy
  template:
    metadata:
      labels:
        k8s-app: kube-proxy
    spec:
      containers:
      - name: kube-proxy
        image: registry.k8s.io/kube-proxy:v1.32.4
        command:
        - /usr/local/bin/kube-proxy
        - --config=/var/lib/kube-proxy/config.conf
        - --hostname-override=\$(NODE_NAME)
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /var/lib/kube-proxy
          name: kube-proxy
        - mountPath: /run/xtables.lock
          name: xtables-lock
        - mountPath: /lib/modules
          name: lib-modules
          readOnly: true
      hostNetwork: true
      priorityClassName: system-node-critical
      serviceAccountName: kube-proxy
      tolerations:
      - operator: Exists
      volumes:
      - name: kube-proxy
        configMap:
          name: kube-proxy
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
      - name: lib-modules
        hostPath:
          path: /lib/modules
EOF

kubectl apply -f /tmp/kube-proxy.yaml

# Ajouter route pour le réseau de service
echo "Ajout de la route pour le réseau de service..."
ip route add 10.96.0.0/12 dev eth0 2>/dev/null || true

# Attendre que les pods système soient prêts
echo "Attente que les pods système démarrent..."
sleep 20

# Retirer le taint du nœud master/control-plane pour permettre le scheduling
echo "Suppression des taints master/control-plane..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
kubectl taint nodes --all node-role.kubernetes.io/master- 2>/dev/null || true

# Vérifier l'état du cluster
echo ""
echo "==================== État du cluster ===================="
kubectl get nodes -o wide
echo ""
echo "==================== Pods système ===================="
kubectl get pods -A -o wide
echo "=========================================================="
echo ""
echo "✅ Installation Kubernetes 1.32.4 terminée avec succès!"
echo ""
echo "Informations utiles:"
echo "  - Version Kubernetes: $(kubectl version --short 2>/dev/null | grep Server || kubectl version -o json | jq -r '.serverVersion.gitVersion')"
echo "  - Runtime: containerd"
echo "  - CNI: Flannel"
echo "  - API Token PWD: disponible via /etc/pki/tokens.csv"
echo ""
echo "Utilisez 'kubectl get nodes' pour vérifier l'état du cluster"
echo "Utilisez 'kubectl get pods -A' pour voir tous les pods"
echo ""
