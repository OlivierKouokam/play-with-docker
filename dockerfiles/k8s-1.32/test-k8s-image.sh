#!/bin/bash
# Script de test automatisé pour k8s-mono 1.32 Ubuntu 24.04

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
IMAGE_NAME="${1:-k8s-mono:1.32-ubuntu24}"
CONTAINER_NAME="k8s-test-$$"
TIMEOUT=180
TEST_PASSED=0
TEST_FAILED=0

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Tests k8s-mono Ubuntu 24.04 + Kubernetes 1.32.4${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Image: $IMAGE_NAME${NC}\n"

# Fonction de nettoyage
cleanup() {
    echo -e "\n${YELLOW}🧹 Nettoyage...${NC}"
    docker stop $CONTAINER_NAME 2>/dev/null || true
    docker rm -f $CONTAINER_NAME 2>/dev/null || true
}

trap cleanup EXIT

# Fonction pour test réussi
test_pass() {
    TEST_PASSED=$((TEST_PASSED + 1))
    echo -e "${GREEN}✅ $1${NC}"
}

# Fonction pour test échoué
test_fail() {
    TEST_FAILED=$((TEST_FAILED + 1))
    echo -e "${RED}❌ $1${NC}"
}

# Test 0: Vérifier que l'image existe
echo -e "${YELLOW}Test 0: Vérification de l'image${NC}"
if docker image inspect "$IMAGE_NAME" &>/dev/null; then
    IMAGE_SIZE=$(docker image inspect "$IMAGE_NAME" --format='{{.Size}}' | awk '{print $1/1024/1024 "MB"}')
    test_pass "Image trouvée (Taille: $IMAGE_SIZE)"
else
    test_fail "Image non trouvée"
    exit 1
fi

# Test 1: Lancement du conteneur
echo -e "\n${YELLOW}Test 1: Lancement du conteneur${NC}"
if docker run --privileged --name $CONTAINER_NAME -d $IMAGE_NAME; then
    test_pass "Conteneur démarré"
else
    test_fail "Échec du démarrage du conteneur"
    exit 1
fi

# Attendre le démarrage
echo -e "${YELLOW}⏳ Attente du démarrage de Kubernetes (${TIMEOUT}s max)...${NC}"
sleep 45

# Test 2: Vérifier systemd
echo -e "\n${YELLOW}Test 2: Vérification de systemd${NC}"
if docker exec $CONTAINER_NAME systemctl is-system-running 2>/dev/null | grep -qE "running|degraded"; then
    test_pass "systemd fonctionne"
else
    test_fail "systemd ne fonctionne pas"
    docker exec $CONTAINER_NAME systemctl status 2>&1 | head -20
fi

# Test 3: Vérifier containerd
echo -e "\n${YELLOW}Test 3: Vérification de containerd${NC}"
if docker exec $CONTAINER_NAME systemctl is-active containerd 2>/dev/null | grep -q "active"; then
    CONTAINERD_VERSION=$(docker exec $CONTAINER_NAME containerd --version | awk '{print $3}')
    test_pass "containerd actif (version: $CONTAINERD_VERSION)"
else
    test_fail "containerd non actif"
    docker exec $CONTAINER_NAME journalctl -u containerd -n 20 2>&1
fi

# Test 4: Vérifier Docker (optionnel)
echo -e "\n${YELLOW}Test 4: Vérification de Docker CE (optionnel)${NC}"
if docker exec $CONTAINER_NAME systemctl is-active docker 2>/dev/null | grep -q "active"; then
    DOCKER_VERSION=$(docker exec $CONTAINER_NAME docker --version | awk '{print $3}')
    test_pass "Docker actif (version: $DOCKER_VERSION)"
else
    echo -e "${YELLOW}⚠️  Docker non actif (optionnel)${NC}"
fi

# Test 5: Vérifier kubelet
echo -e "\n${YELLOW}Test 5: Vérification de kubelet${NC}"
sleep 10
if docker exec $CONTAINER_NAME systemctl is-active kubelet 2>/dev/null | grep -q "active"; then
    test_pass "kubelet actif"
else
    echo -e "${YELLOW}⚠️  kubelet pas encore actif (normal pendant l'init)${NC}"
fi

# Attendre l'init complète
echo -e "${YELLOW}⏳ Attente de l'initialisation complète (max ${TIMEOUT}s)...${NC}"
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if docker exec $CONTAINER_NAME kubectl get nodes 2>/dev/null | grep -q "Ready"; then
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done
echo ""

# Test 6: Vérifier la version de Kubernetes
echo -e "\n${YELLOW}Test 6: Vérification de la version Kubernetes${NC}"
K8S_VERSION=$(docker exec $CONTAINER_NAME kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' 2>/dev/null || echo "unknown")
if [[ "$K8S_VERSION" =~ "v1.32" ]]; then
    test_pass "Version Kubernetes: $K8S_VERSION"
else
    test_fail "Version Kubernetes incorrecte: $K8S_VERSION (attendu: v1.32.x)"
fi

# Test 7: Vérifier les nœuds
echo -e "\n${YELLOW}Test 7: Vérification des nœuds${NC}"
if docker exec $CONTAINER_NAME kubectl get nodes 2>/dev/null | grep -q "Ready"; then
    NODE_NAME=$(docker exec $CONTAINER_NAME kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
    NODE_STATUS=$(docker exec $CONTAINER_NAME kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')
    test_pass "Nœud $NODE_NAME est $NODE_STATUS"
    docker exec $CONTAINER_NAME kubectl get nodes -o wide
else
    test_fail "Nœud non prêt"
    docker exec $CONTAINER_NAME kubectl get nodes 2>&1
    echo -e "\n${YELLOW}Logs kubelet:${NC}"
    docker exec $CONTAINER_NAME journalctl -u kubelet -n 30 2>&1
fi

# Test 8: Vérifier les pods système
echo -e "\n${YELLOW}Test 8: Vérification des pods système${NC}"
SYSTEM_PODS=$(docker exec $CONTAINER_NAME kubectl get pods -A --no-headers 2>/dev/null | wc -l)
if [ $SYSTEM_PODS -gt 0 ]; then
    test_pass "$SYSTEM_PODS pods système trouvés"
    docker exec $CONTAINER_NAME kubectl get pods -A -o wide
else
    test_fail "Aucun pod système trouvé"
fi

# Test 9: Vérifier les pods critiques
echo -e "\n${YELLOW}Test 9: Vérification des pods critiques${NC}"
CRITICAL_PODS=("etcd" "kube-apiserver" "kube-controller-manager" "kube-scheduler" "coredns")

for pod in "${CRITICAL_PODS[@]}"; do
    POD_STATUS=$(docker exec $CONTAINER_NAME kubectl get pods -n kube-system -l component=$pod -o jsonpath='{.items[0].status.phase}' 2>/dev/null || \
                 docker exec $CONTAINER_NAME kubectl get pods -n kube-system | grep $pod | awk '{print $3}' | head -1)
    
    if [[ "$POD_STATUS" == "Running" ]]; then
        test_pass "Pod $pod est Running"
    else
        test_fail "Pod $pod n'est pas Running (Status: $POD_STATUS)"
    fi
done

# Test 10: Vérifier Flannel
echo -e "\n${YELLOW}Test 10: Vérification du réseau Flannel${NC}"
FLANNEL_PODS=$(docker exec $CONTAINER_NAME kubectl get pods -n kube-flannel --no-headers 2>/dev/null | grep "Running" | wc -l)
if [ $FLANNEL_PODS -gt 0 ]; then
    test_pass "Flannel opérationnel ($FLANNEL_PODS pods)"
else
    echo -e "${YELLOW}⚠️  Flannel pourrait ne pas être encore prêt${NC}"
    docker exec $CONTAINER_NAME kubectl get pods -n kube-flannel 2>&1
fi

# Test 11: Vérifier kube-proxy
echo -e "\n${YELLOW}Test 11: Vérification de kube-proxy${NC}"
PROXY_PODS=$(docker exec $CONTAINER_NAME kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null | grep "Running" | wc -l)
if [ $PROXY_PODS -gt 0 ]; then
    test_pass "kube-proxy opérationnel ($PROXY_PODS pods)"
else
    test_fail "kube-proxy non trouvé ou non Running"
fi

# Test 12: Déployer une application test
echo -e "\n${YELLOW}Test 12: Déploiement d'une application test${NC}"
if docker exec $CONTAINER_NAME kubectl create deployment nginx-test --image=nginx:alpine 2>/dev/null; then
    test_pass "Déploiement nginx créé"
    
    # Attendre que le pod soit prêt
    echo -e "${YELLOW}⏳ Attente que le pod nginx soit prêt...${NC}"
    ELAPSED=0
    while [ $ELAPSED -lt 90 ]; do
        POD_STATUS=$(docker exec $CONTAINER_NAME kubectl get pods -l app=nginx-test -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
        if [[ "$POD_STATUS" == "Running" ]]; then
            test_pass "Pod nginx-test est Running"
            break
        fi
        sleep 3
        ELAPSED=$((ELAPSED + 3))
        echo -n "."
    done
    echo ""
    
    if [[ "$POD_STATUS" != "Running" ]]; then
        test_fail "Pod nginx-test n'est pas Running après 90s"
        docker exec $CONTAINER_NAME kubectl describe pod -l app=nginx-test 2>&1 | tail -30
    fi
    
    # Nettoyer
    docker exec $CONTAINER_NAME kubectl delete deployment nginx-test 2>/dev/null || true
else
    test_fail "Échec de la création du déploiement"
fi

# Test 13: Vérifier le runtime containerd
echo -e "\n${YELLOW}Test 13: Vérification du runtime containerd${NC}"
if docker exec $CONTAINER_NAME ctr version 2>/dev/null | grep -q "Version:"; then
    CTR_VERSION=$(docker exec $CONTAINER_NAME ctr version | grep "Version:" | head -1 | awk '{print $2}')
    test_pass "ctr (containerd CLI) fonctionne (version: $CTR_VERSION)"
else
    test_fail "ctr ne fonctionne pas"
fi

# Test 14: Vérifier les outils installés
echo -e "\n${YELLOW}Test 14: Vérification des outils installés${NC}"
TOOLS=("kubectl" "kubeadm" "kubelet" "docker" "jq" "git" "docker-compose")
for tool in "${TOOLS[@]}"; do
    if docker exec $CONTAINER_NAME which $tool >/dev/null 2>&1; then
        VERSION=$(docker exec $CONTAINER_NAME $tool --version 2>&1 | head -1 | cut -d' ' -f1-3 || echo "N/A")
        test_pass "$tool installé: $VERSION"
    else
        echo -e "${YELLOW}⚠️  $tool non trouvé${NC}"
    fi
done

# Test 15: Vérifier l'autocomplétion kubectl
echo -e "\n${YELLOW}Test 15: Vérification de l'autocomplétion kubectl${NC}"
if docker exec $CONTAINER_NAME bash -c "complete -p kubectl" 2>/dev/null | grep -q "kubectl"; then
    test_pass "Autocomplétion kubectl configurée"
else
    echo -e "${YELLOW}⚠️  Autocomplétion kubectl non configurée${NC}"
fi

# Test 16: Vérifier les tokens PWD
echo -e "\n${YELLOW}Test 16: Vérification des tokens PWD${NC}"
if docker exec $CONTAINER_NAME test -f /etc/pki/tokens.csv; then
    TOKEN_COUNT=$(docker exec $CONTAINER_NAME wc -l < /etc/pki/tokens.csv)
    test_pass "Fichier tokens.csv présent ($TOKEN_COUNT tokens)"
else
    test_fail "Fichier tokens.csv non trouvé"
fi

# Test 17: Vérifier la configuration réseau
echo -e "\n${YELLOW}Test 17: Vérification de la configuration réseau${NC}"
if docker exec $CONTAINER_NAME ip route | grep -q "10.96.0.0/12"; then
    test_pass "Route vers le réseau de service configurée"
else
    echo -e "${YELLOW}⚠️  Route vers le réseau de service non trouvée${NC}"
    docker exec $CONTAINER_NAME ip route show
fi

# Test 18: Test de résolution DNS
echo -e "\n${YELLOW}Test 18: Test de résolution DNS${NC}"
if docker exec $CONTAINER_NAME kubectl run -it --rm dns-test --image=busybox:latest --restart=Never -- nslookup kubernetes.default 2>&1 | grep -q "Address"; then
    test_pass "Résolution DNS fonctionne"
else
    echo -e "${YELLOW}⚠️  Test DNS échoué (peut être normal si CoreDNS n'est pas encore prêt)${NC}"
fi

# Résumé final
echo -e "\n${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    RÉSUMÉ DES TESTS${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Tests réussis: $TEST_PASSED${NC}"
echo -e "${RED}Tests échoués: $TEST_FAILED${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

# Informations supplémentaires
echo -e "\n${YELLOW}📊 Informations système:${NC}"
docker exec $CONTAINER_NAME bash -c "
echo '  OS: '\$(cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2)
echo '  Kernel: '\$(uname -r)
echo '  Kubernetes: '\$(kubectl version --short 2>/dev/null | grep Server || kubectl version -o json | jq -r '.serverVersion.gitVersion')
echo '  containerd: '\$(containerd --version | awk '{print \$3}')
echo '  Docker: '\$(docker --version | awk '{print \$3}')
"

echo -e "\n${YELLOW}📝 Pour examiner le conteneur:${NC}"
echo -e "  docker exec -it $CONTAINER_NAME bash"
echo -e "\n${YELLOW}📋 Pour voir les logs:${NC}"
echo -e "  docker logs $CONTAINER_NAME"
echo -e "\n${YELLOW}🔍 Pour voir les pods:${NC}"
echo -e "  docker exec $CONTAINER_NAME kubectl get pods -A"

if [ $TEST_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 TOUS LES TESTS SONT PASSÉS !${NC}"
    echo -e "${GREEN}L'image est prête pour le déploiement.${NC}"
    EXIT_CODE=0
else
    echo -e "\n${RED}⚠️  CERTAINS TESTS ONT ÉCHOUÉ${NC}"
    echo -e "${YELLOW}Vérifiez les logs ci-dessus pour plus de détails.${NC}"
    EXIT_CODE=1
fi

echo -e "\n${RED}Le conteneur sera nettoyé dans 10 secondes...${NC}"
echo -e "${YELLOW}Appuyez sur Ctrl+C pour le garder.${NC}"
sleep 10

exit $EXIT_CODE
