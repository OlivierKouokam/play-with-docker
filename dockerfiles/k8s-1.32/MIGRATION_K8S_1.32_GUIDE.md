# Migration k8s-mono vers Ubuntu 24.04 + Kubernetes 1.32.4 + containerd

## 🎯 Objectifs de la migration

- ✅ Base OS: CentOS 7 → Ubuntu 24.04 LTS
- ✅ Kubernetes: 1.18.4 → 1.32.4 (dernière version stable)
- ✅ Runtime: Docker 19.03 → containerd 1.7 (+ Docker CE optionnel)
- ✅ CNI: Flannel (version mise à jour)
- ✅ Compatibilité: Maintien de toutes les fonctionnalités PWD

## 📋 Changements majeurs

### Runtime de conteneurs
```
AVANT (k8s 1.18 + CentOS 7):
- Docker 19.03.15 comme runtime
- dockershim intégré dans kubelet
- VFS storage driver

APRÈS (k8s 1.32 + Ubuntu 24.04):
- containerd comme runtime principal
- Socket CRI: unix:///var/run/containerd/containerd.sock
- overlay2 storage driver
- Docker CE disponible pour docker-compose (optionnel)
```

### Configuration kubelet
```
CHANGEMENTS CLÉS:
1. --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock
2. --cgroup-driver=systemd (au lieu de cgroupfs)
3. --network-plugin=cni (standard CNI)
4. Suppression de --pod-infra-container-image (géré par containerd)
```

### API Kubernetes
```
APIS CHANGÉES (1.18 → 1.32):

DÉPRÉCIÉES/SUPPRIMÉES:
- extensions/v1beta1 → networking.k8s.io/v1 (Ingress)
- rbac.authorization.k8s.io/v1beta1 → v1
- apiextensions.k8s.io/v1beta1 → v1

NOUVELLES:
- kubeadm.k8s.io/v1beta4 (API kubeadm)
- Ephemeral Containers (debug)
- Pod Security Standards
```

### Configuration kubeadm
```yaml
# AVANT (v1beta2 - k8s 1.18):
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration

# APRÈS (v1beta4 - k8s 1.32):
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
```

## 🔧 Fichiers modifiés

### 1. Dockerfile
**Changements principaux:**
- `FROM centos:7` → `FROM ubuntu:24.04`
- `yum install` → `apt-get install`
- Repos Kubernetes mis à jour (pkgs.k8s.io/core:/stable:/v1.32)
- Installation containerd + configuration SystemdCgroup
- Docker CE optionnel (pour docker-compose)

### 2. kubelet.env
**Nouveaux paramètres:**
```bash
# Runtime endpoint pour containerd
KUBELET_RUNTIME_ARGS="--container-runtime-endpoint=unix:///var/run/containerd/containerd.sock"

# Cgroup driver systemd
KUBELET_CGROUP_ARGS="--cgroup-driver=systemd"

# Suppression de --pod-infra-container-image
```

### 3. kubelet.service
**Modifications:**
```ini
[Unit]
After=network-online.target containerd.service  # Ajout containerd

[Service]
Type=notify  # Ajouté pour k8s 1.32
```

### 4. deploy-k8s.sh
**Nouvelles fonctionnalités:**
- Configuration kubeadm v1beta4
- Skip kube-proxy pendant init (installé manuellement après)
- Configuration kube-proxy avec masquerade-all et conntrack=0
- Support containerd natif
- Flannel latest version

### 5. wrapkubeadm.sh
**Adaptations:**
- Support de l'API v1beta4
- Configuration token-auth via volumes
- Gestion moderne de kube-proxy (ConfigMap)
- Suppression des références à etcd2

### 6. systemctl (custom)
**Conservé à l'identique** - Fonctionne sur Ubuntu 24.04

### 7. daemon.json (Docker)
**Changements:**
```json
{
    "exec-opts": ["native.cgroupdriver=systemd"],  // Nouveau
    "storage-driver": "overlay2",                  // overlay2 au lieu de vfs
    "insecure-registries": ["127.0.0.1"],
    "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"]
}
```

### 8. Fichiers inchangés
- `tokens.csv` - ✅ Compatible
- `resolv.conf.override` - ✅ Compatible
- `motd` - ✅ Compatible

## 🚀 Procédure de migration

### Étape 1: Préparer l'environnement

```bash
# Sur l'hôte Ubuntu 24.04
sudo modprobe overlay
sudo modprobe br_netfilter
sudo modprobe xt_ipvs

# Rendre permanent
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
xt_ipvs
EOF

# Configuration sysctl
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Docker Swarm pour PWD
docker swarm init
```

### Étape 2: Organiser les fichiers

```bash
# Structure recommandée
dockerfiles/k8s-1.32-mono/
├── Dockerfile              # Nouveau Dockerfile Ubuntu 24.04
├── deploy-k8s.sh          # Script modernisé
├── kubelet.env            # Config kubelet pour containerd
├── kubelet.service        # Service systemd kubelet
├── wrapkubeadm.sh        # Wrapper kubeadm adapté
├── systemctl             # Script custom (inchangé)
├── tokens.csv            # Tokens k8s (inchangé)
├── daemon.json           # Config Docker moderne
├── resolv.conf.override  # Config DNS (inchangé)
└── motd                  # Message accueil (inchangé)
```

### Étape 3: Build de l'image

```bash
cd dockerfiles/k8s-1.32-mono/

# Build
docker build -t k8s-mono:1.32-ubuntu24 .

# Vérifier la taille
docker images k8s-mono:1.32-ubuntu24
```

### Étape 4: Tests

#### Test 1: Démarrage basique
```bash
docker run --privileged --name k8s-test -d k8s-mono:1.32-ubuntu24

# Attendre 2-3 minutes
sleep 120

# Vérifier les logs
docker logs k8s-test

# Se connecter
docker exec -it k8s-test bash
```

#### Test 2: Vérifier k8s
```bash
# Dans le conteneur
kubectl get nodes
kubectl get pods -A
kubectl version

# Vérifier containerd
systemctl status containerd
ctr version

# Vérifier les pods système
kubectl get pods -n kube-system -o wide
```

#### Test 3: Déployer une application
```bash
# Test nginx
kubectl create deployment nginx --image=nginx:latest
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc

# Tester l'accès
NODE_PORT=$(kubectl get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
curl http://localhost:$NODE_PORT

# Nettoyer
kubectl delete deployment nginx
kubectl delete service nginx
```

#### Test 4: Intégration PWD
```bash
# Tester dans l'environnement PWD complet
# 1. Créer plusieurs instances (3-5)
# 2. Vérifier le réseau overlay
# 3. Tester la communication inter-instances
# 4. Vérifier le port forwarding

# Depuis instance 1:
kubectl run test-pod --image=nginx --port=80
kubectl expose pod test-pod --type=NodePort

# Depuis instance 2:
INSTANCE1_IP=10.0.0.1  # IP de l'instance 1
curl http://$INSTANCE1_IP:<nodeport>
```

### Étape 5: Déploiement

```bash
# Tag pour votre registry
docker tag k8s-mono:1.32-ubuntu24 votre-registry/k8s-mono:1.32-ubuntu24
docker tag k8s-mono:1.32-ubuntu24 votre-registry/k8s-mono:latest

# Push
docker push votre-registry/k8s-mono:1.32-ubuntu24
docker push votre-registry/k8s-mono:latest

# Mettre à jour la configuration PWD
# Modifier le fichier de config pour pointer vers la nouvelle image
```

## 🐛 Dépannage

### Problème: containerd ne démarre pas
```bash
# Vérifier les logs
journalctl -u containerd -n 50

# Vérifier la config
cat /etc/containerd/config.toml | grep SystemdCgroup
# Doit être: SystemdCgroup = true

# Redémarrer
systemctl restart containerd
```

### Problème: kubelet ne démarre pas
```bash
# Vérifier les logs
journalctl -u kubelet -n 50

# Vérifier le socket containerd
ls -la /var/run/containerd/containerd.sock

# Vérifier les flags kubelet
cat /etc/systemd/system/kubelet.env
```

### Problème: Pods en Pending
```bash
# Vérifier les events
kubectl get events --sort-by='.lastTimestamp'

# Vérifier Flannel
kubectl get pods -n kube-flannel

# Vérifier les routes
ip route show

# Vérifier iptables
iptables -L -n -v -t nat | grep KUBE
```

### Problème: DNS ne fonctionne pas
```bash
# Vérifier CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Tester DNS
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Vérifier resolv.conf
cat /etc/resolv.conf.override
```

### Problème: kube-proxy issues
```bash
# Vérifier kube-proxy
kubectl get ds -n kube-system kube-proxy
kubectl logs -n kube-system -l k8s-app=kube-proxy

# Recréer kube-proxy
kubectl delete ds -n kube-system kube-proxy
# Puis relancer deploy-k8s.sh
```

## 📊 Comparaison des versions

| Fonctionnalité | k8s 1.18 (ancien) | k8s 1.32 (nouveau) |
|----------------|-------------------|---------------------|
| **Runtime** | Docker 19.03 | containerd 1.7 |
| **Cgroup driver** | cgroupfs | systemd |
| **Storage driver** | vfs | overlay2 |
| **CNI** | Flannel 0.23 | Flannel latest |
| **kubeadm API** | v1beta2 | v1beta4 |
| **Support** | EOL (2020) | Actif jusqu'à 2025 |
| **Sécurité** | Vulnérabilités | Patches récents |
| **Performance** | Bonne | Excellente |

## ✅ Checklist finale

Avant de déployer en production:

- [ ] Build réussi sans erreurs
- [ ] Image testée en local
- [ ] Cluster k8s démarre correctement
- [ ] Tous les pods système sont Running
- [ ] Déploiement d'app test réussi
- [ ] Réseau overlay PWD fonctionne
- [ ] Communication inter-instances OK
- [ ] Port forwarding testé
- [ ] Tokens PWD fonctionnent
- [ ] DNS résolution OK
- [ ] Performances acceptables
- [ ] Logs clean (pas d'erreurs critiques)
- [ ] Documentation mise à jour
- [ ] Plan de rollback prêt

## 🔄 Plan de rollback

En cas de problème:

```bash
# 1. Revenir à l'ancienne image
docker pull votre-registry/k8s-mono:centos7-backup

# 2. Mettre à jour la config PWD
# Pointer vers l'ancienne image

# 3. Redémarrer les instances
# Les nouvelles instances utiliseront l'ancienne image

# 4. Investiguer les logs
# Identifier le problème avant de retenter
```

## 📈 Prochaines étapes

Après migration réussie:

1. **Monitoring**: Surveiller les métriques pendant 48h
2. **Documentation**: Mettre à jour la doc utilisateur
3. **Formation**: Informer les utilisateurs des changements
4. **Optimisation**: Tuner les ressources si nécessaire
5. **Automatisation**: Améliorer les scripts de déploiement

## 💡 Bonnes pratiques

1. **Tests graduels**: Tester avec 1 instance, puis 3, puis 5
2. **Fenêtre de maintenance**: Planifier une fenêtre de 2-4h
3. **Communication**: Prévenir les utilisateurs à l'avance
4. **Backup**: Garder l'ancienne image disponible 1 mois
5. **Monitoring**: Surveiller activement pendant la transition

---

**Version:** 1.0  
**Date:** 2025  
**Auteur:** Migration k8s 1.18 → 1.32
