# Makefile pour k8s-mono Ubuntu 24.04 + Kubernetes 1.32.4

IMAGE_NAME ?= k8s-mono
TAG ?= 1.32-ubuntu24
REGISTRY ?= your-registry.com
FULL_IMAGE = $(IMAGE_NAME):$(TAG)
REGISTRY_IMAGE = $(REGISTRY)/$(FULL_IMAGE)

.PHONY: help build test push clean shell logs check-files

help:
	@echo "════════════════════════════════════════════════════════"
	@echo "  Makefile k8s-mono Ubuntu 24.04 + Kubernetes 1.32"
	@echo "════════════════════════════════════════════════════════"
	@echo ""
	@echo "Commandes disponibles:"
	@echo "  make build         - Builder l'image k8s 1.32"
	@echo "  make test          - Tester l'image (automatique)"
	@echo "  make test-manual   - Lancer un conteneur pour test manuel"
	@echo "  make push          - Pousser vers le registry"
	@echo "  make shell         - Ouvrir un shell dans l'image"
	@echo "  make logs          - Voir les logs du conteneur de test"
	@echo "  make clean         - Nettoyer les conteneurs de test"
	@echo "  make check-files   - Vérifier la présence des fichiers requis"
	@echo "  make all           - Build + Test + Push"
	@echo ""
	@echo "Variables:"
	@echo "  IMAGE_NAME=$(IMAGE_NAME)"
	@echo "  TAG=$(TAG)"
	@echo "  REGISTRY=$(REGISTRY)"
	@echo ""

check-files:
	@echo "🔍 Vérification des fichiers requis..."
	@test -f Dockerfile || (echo "❌ Dockerfile manquant" && exit 1)
	@test -f deploy-k8s.sh || (echo "❌ deploy-k8s.sh manquant" && exit 1)
	@test -f kubelet.service || (echo "❌ kubelet.service manquant" && exit 1)
	@test -f kubelet.env || (echo "❌ kubelet.env manquant" && exit 1)
	@test -f wrapkubeadm.sh || (echo "❌ wrapkubeadm.sh manquant" && exit 1)
	@test -f systemctl || (echo "❌ systemctl manquant" && exit 1)
	@test -f tokens.csv || (echo "❌ tokens.csv manquant" && exit 1)
	@test -f daemon.json || (echo "❌ daemon.json manquant" && exit 1)
	@test -f resolv.conf.override || (echo "❌ resolv.conf.override manquant" && exit 1)
	@test -f motd || (echo "❌ motd manquant" && exit 1)
	@echo "✅ Tous les fichiers requis sont présents"

build: check-files
	@echo "🔨 Building image $(FULL_IMAGE)..."
	docker build -t $(FULL_IMAGE) .
	@echo "✅ Image built: $(FULL_IMAGE)"
	@docker images $(IMAGE_NAME)

test: build
	@echo "🧪 Testing image $(FULL_IMAGE)..."
	@chmod +x test-k8s-image.sh
	./test-k8s-image.sh $(FULL_IMAGE)

test-manual: build
	@echo "🚀 Lancement d'un conteneur de test manuel..."
	@docker run --rm --privileged --name k8s-test-manual -d $(FULL_IMAGE) || true
	@echo ""
	@echo "✅ Conteneur lancé: k8s-test-manual"
	@echo ""
	@echo "Commandes utiles:"
	@echo "  docker logs -f k8s-test-manual          # Voir les logs"
	@echo "  docker exec -it k8s-test-manual bash    # Se connecter"
	@echo "  docker exec k8s-test-manual kubectl get nodes"
	@echo "  docker exec k8s-test-manual kubectl get pods -A"
	@echo ""
	@echo "Pour arrêter: docker stop k8s-test-manual"

push: build
	@echo "📤 Pushing image to registry..."
	docker tag $(FULL_IMAGE) $(REGISTRY_IMAGE)
	docker tag $(FULL_IMAGE) $(REGISTRY)/$(IMAGE_NAME):latest
	docker push $(REGISTRY_IMAGE)
	docker push $(REGISTRY)/$(IMAGE_NAME):latest
	@echo "✅ Image pushed to registry"

shell: build
	@echo "🐚 Opening shell in $(FULL_IMAGE)..."
	docker run --rm -it --privileged $(FULL_IMAGE) /bin/bash

logs:
	@echo "📋 Logs du conteneur de test..."
	@docker logs k8s-test-manual 2>/dev/null || echo "❌ Aucun conteneur k8s-test-manual en cours"

clean:
	@echo "🧹 Cleaning up test containers..."
	@docker stop k8s-test-manual 2>/dev/null || true
	@docker rm -f k8s-test-manual 2>/dev/null || true
	@docker ps -a | grep "k8s-test-" | awk '{print $$1}' | xargs -r docker rm -f 2>/dev/null || true
	@echo "✅ Cleanup complete"

all: build test push
	@echo ""
	@echo "════════════════════════════════════════════════════════"
	@echo "  ✅ Build, Test, and Push completed successfully!"
	@echo "════════════════════════════════════════════════════════"

.DEFAULT_GOAL := help
