# k8s-mono Ubuntu 24.04 + Kubernetes 1.32.4 + containerd

## 📦 Package de migration complet

Ce package contient tout le nécessaire pour migrer votre image k8s-mono de **CentOS 7 + k8s 1.18 + Docker** vers **Ubuntu 24.04 + k8s 1.32 + containerd**.

## 🎯 Spécifications

- **OS**: Ubuntu 24.04 LTS
- **Kubernetes**: v1.32.4 (dernière version stable)
- **Runtime**: containerd 1.7+ (Docker CE optionnel)
- **CNI**: Flannel (dernière version)
- **Cgroup driver**: systemd
- **Storage driver**: overlay2
- **Compatibilité**: Play with Docker (PWD)

## 📁 Fichiers fournis

### Fichiers Docker
1. **Dockerfile** - Image Ubuntu 24.04 avec k8s 1.32.4 et containerd
2. **daemon.json** - Configuration Docker moderne

### Scripts
3. **deploy-k8s.sh** - Script de déploiement k8s 1.32
4. **wrapkubeadm.sh** - Wrapper kubeadm adapté pour PWD
5. **test-k8s-image.sh** - Tests automatisés complets
6. **systemctl** - Script systemctl customisé (conservé)

### Configuration Kubernetes
7. **kubelet.service** - Service systemd pour kubelet
8. **kubelet.env** - Variables d'environnement kubelet
9. **tokens.csv** - Tokens d'authentification PWD
10. **resolv.conf.override** - Configuration DNS
11. **motd** - Message d'accueil

### Utilitaires
12. **Makefile** - Commandes simplifiées
13. **MIGRATION_K8S_1.32_GUIDE.md** - Guide détaillé de migration

## 🚀 Quick Start

### Prérequis sur l'hôte Ubuntu 24.04

```bash
# Charger les modules kernel
sudo modprobe overlay br_netfilter xt_ipvs

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

### Installation rapide

```bash
# 1. Copier tous les fichiers dans dockerfiles/k8s-1.32-mono/
mkdir -p dockerfiles/k8s-1.32-mono/
cp Dockerfile deploy-k8s.sh kubelet.* wrapkubeadm.sh systemctl \
   tokens.csv daemon.json resolv.conf.override motd \
   dockerfiles/k8s-1.32-mono/

# 2. Se déplacer dans le répertoire
cd dockerfiles/k8s-1.32-mono/

# 3. Vérifier les fichiers
make check-files

# 4. Builder l'image
make build

# 5. Tester
make test

# 6. Push vers registry (adapter REGISTRY dans Makefile)
make push
```

## 🔧 Utilisation du Makefile

```bash
# Voir toutes les commandes
make help

# Builder l'image
make build

# Tester automatiquement
make test

# Test manuel (garde le conteneur)
make test-manual

# Shell interactif
make shell

# Pousser vers registry
make push

# Tout faire (build + test + push)
make all

# Nettoyer
make clean
```

## 🧪 Tests

Le script `test-k8s-image.sh` effectue 18 tests automatisés :

1. ✅ Vérification de l'image
2. ✅ Lancement du conteneur
3. ✅ Vérification systemd
4. ✅ Vérification containerd
5. ✅ Vérification Docker (optionnel)
6. ✅ Vérification kubelet
7. ✅ Version Kubernetes
8. ✅ État des nœuds
9. ✅ Pods système
10. ✅ Pods critiques (etcd, apiserver, etc.)
11. ✅ Réseau Flannel
12. ✅ kube-proxy
13. ✅ Déploiement d'une app test
14. ✅ Runtime containerd
15. ✅ Outils installés
16. ✅ Autocomplétion kubectl
17. ✅ Tokens PWD
18. ✅ Configuration réseau

### Exécution des tests

```bash
# Tests automatisés
./test-k8s-image.sh k8s-mono:1.32-ubuntu24

# Ou via Makefile
make test
```

## 📊 Différences avec l'ancienne version

| Aspect | CentOS 7 (ancien) | Ubuntu 24.04 (nouveau) |
|--------|-------------------|------------------------|
| **OS** | CentOS 7 | Ubuntu 24.04 LTS |
| **Kubernetes** | 1.18.4 (EOL) | 1.32.4 (actif) |
| **Runtime** | Docker 19.03 | containerd 1.7 |
| **Cgroup** | cgroupfs | systemd |
| **Storage** | vfs | overlay2 |
| **kubeadm API** | v1beta2 | v1beta4 |
| **Support** | EOL 2020 | Support jusqu'en 2025+ |

## 🔍 Points clés de la migration

### 1. Runtime containerd

```bash
# L'image utilise containerd par défaut
KUBELET_RUNTIME_ARGS="--container-runtime-endpoint=unix:///var/run/containerd/containerd.sock"

# Docker CE est aussi disponible (optionnel)
# Pour docker-compose et compatibilité
```

### 2. Configuration kubeadm v1beta4

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.32.4
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
```

### 3. Cgroup driver systemd

```bash
# Dans kubelet.env
KUBELET_CGROUP_ARGS="--cgroup-driver=systemd"

# Dans /etc/containerd/config.toml
SystemdCgroup = true
```

### 4. Token authentication PWD

Le fichier `tokens.csv` est automatiquement monté dans l'API server :

```yaml
extraVolumes:
  - name: tokens
    hostPath: /etc/pki/tokens.csv
    mountPath: /etc/pki/tokens.csv
```

## 🐛 Dépannage

### Conteneur ne démarre pas

```bash
# Vérifier les logs
docker logs <container-name>

# Vérifier systemd
docker exec <container-name> systemctl status
```

### containerd ne démarre pas

```bash
# Logs containerd
docker exec <container-name> journalctl -u containerd -n 50

# Vérifier la config
docker exec <container-name> cat /etc/containerd/config.toml | grep SystemdCgroup
```

### kubelet ne démarre pas

```bash
# Logs kubelet
docker exec <container-name> journalctl -u kubelet -n 50

# Vérifier le socket containerd
docker exec <container-name> ls -la /var/run/containerd/containerd.sock
```

### Pods en Pending

```bash
# Events
docker exec <container-name> kubectl get events --sort-by='.lastTimestamp'

# Vérifier Flannel
docker exec <container-name> kubectl get pods -n kube-flannel

# Vérifier les routes
docker exec <container-name> ip route
```

### DNS ne fonctionne pas

```bash
# Vérifier CoreDNS
docker exec <container-name> kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS
docker exec <container-name> kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
```

## 🔐 Sécurité

### Tokens PWD

Le fichier `tokens.csv` contient :

```csv
31ada4fd-adec-460c-809a-9e56ceb75269,pwd,pwd,"system:admin,system:masters"
```

**⚠️ Important**: Ces tokens sont pour l'environnement PWD uniquement. Ne pas utiliser en production.

### Conteneur privilégié

L'image nécessite `--privileged` pour :
- Gérer systemd
- Créer des namespaces réseau
- Monter des systèmes de fichiers
- Gérer iptables

## 📈 Performances

### Taille de l'image

```bash
# Voir la taille
docker images k8s-mono:1.32-ubuntu24
```

Taille estimée : ~1.5-2 GB (optimisée avec apt clean et multi-stage si possible)

### Temps de démarrage

- Démarrage du conteneur : ~5 secondes
- Initialisation k8s : ~60-90 secondes
- Cluster complètement opérationnel : ~2-3 minutes

## 🔄 Intégration PWD

### Configuration PWD

Mettre à jour votre configuration PWD pour pointer vers la nouvelle image :

```yaml
# Dans votre config PWD
images:
  k8s:
    name: "votre-registry/k8s-mono:1.32-ubuntu24"
    privileged: true
```

### Test multi-instances

```bash
# 1. Créer 3 instances dans PWD
# 2. Dans instance 1:
kubectl run nginx --image=nginx --port=80
kubectl expose pod nginx --type=NodePort

# 3. Dans instance 2:
INSTANCE1_IP=10.0.0.1
NODE_PORT=$(kubectl -s http://$INSTANCE1_IP:8080 get svc nginx -o jsonpath='{.spec.ports[0].nodePort}')
curl http://$INSTANCE1_IP:$NODE_PORT

# Devrait fonctionner grâce au réseau overlay
```

## 📚 Documentation supplémentaire

- **MIGRATION_K8S_1.32_GUIDE.md** - Guide détaillé de migration
- **Kubernetes 1.32 Release Notes** - https://kubernetes.io/blog/2024/12/11/kubernetes-v1-32-release/
- **containerd Documentation** - https://containerd.io/docs/

## ✅ Checklist de déploiement

Avant le déploiement en production :

- [ ] Build réussi sans erreurs
- [ ] Tous les tests automatisés passent
- [ ] Test manuel effectué
- [ ] Cluster k8s démarre en <3 minutes
- [ ] Pods système Running
- [ ] Déploiement nginx test OK
- [ ] Réseau overlay PWD fonctionne
- [ ] Communication inter-instances OK
- [ ] Port forwarding testé
- [ ] Tokens PWD valides
- [ ] DNS résolution OK
- [ ] Performances acceptables
- [ ] Documentation mise à jour
- [ ] Plan de rollback prêt

## 🆘 Support

En cas de problème :

1. Vérifier les logs : `docker logs <container>`
2. Vérifier systemd : `docker exec <container> systemctl status`
3. Vérifier kubelet : `docker exec <container> journalctl -u kubelet`
4. Consulter le guide de migration
5. Tester avec l'ancienne image pour comparer

## 📝 Notes de version

### v1.0 - Migration initiale
- Migration CentOS 7 → Ubuntu 24.04
- Kubernetes 1.18.4 → 1.32.4
- Docker runtime → containerd
- Tests automatisés complets
- Documentation complète

---

**Auteur**: Migration Assistant  
**Date**: Janvier 2025  
**Version**: 1.0  
**Kubernetes**: v1.32.4  
**Ubuntu**: 24.04 LTS
