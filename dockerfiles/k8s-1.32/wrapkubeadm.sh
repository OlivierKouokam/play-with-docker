#!/bin/bash 
# Wrapper kubeadm pour PWD - Adapté pour Kubernetes 1.32
# Copyright 2017 Mirantis - Modifié pour k8s 1.32 et containerd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

set -o pipefail
set -o errtrace

# Chemins pour k8s 1.32
apiserver_static_pod="/etc/kubernetes/manifests/kube-apiserver.yaml"

# jq filter pour activer l'authentification par token
apiserver_token_auth='.spec.containers[0].command|=map(select(startswith("--token-auth-file")|not))+["--token-auth-file=/etc/pki/tokens.csv"]'

# Ajoute le volume pour les tokens dans le pod apiserver
apiserver_token_volume='
  .spec.volumes += [{
    "name": "tokens",
    "hostPath": {
      "path": "/etc/pki/tokens.csv",
      "type": "File"
    }
  }] |
  .spec.containers[0].volumeMounts += [{
    "name": "tokens",
    "mountPath": "/etc/pki/tokens.csv",
    "readOnly": true
  }]
'

function dind::join-filters {
  local IFS="|"
  echo "$*"
}

function dind::frob-apiserver {
  if [[ -f "${apiserver_static_pod}" ]]; then
    echo "Modification de l'API server pour supporter l'auth par token..."
    local filter="$(dind::join-filters "${apiserver_token_auth}" "${apiserver_token_volume}")"
    dind::yq "${filter}" "${apiserver_static_pod}"
  fi
}

function dind::yq {
  local filter="$1"
  local path="$2"
  
  # Utiliser yq moderne (compatible avec k8s 1.32)
  if command -v yq &> /dev/null; then
    # yq v4 syntax
    yq eval "${filter}" -i "${path}"
  else
    # Fallback to kubectl convert + jq
    tmp="$(mktemp tmp-XXXXXXXXXX.yaml)"
    kubectl convert -f "${path}" --local -o json 2>/dev/null | \
      jq "${filter}" | \
      kubectl convert -f - --local -o yaml 2>/dev/null > "${tmp}"
    mv "${tmp}" "${path}"
  fi
}

# Met à jour kube-proxy pour PWD (DIND)
# - Définit le bon cluster CIDR
# - Active masquerade-all
# - Désactive conntrack (problèmes dans conteneurs privilégiés)
function dind::proxy-cidr-and-no-conntrack {
  cluster_cidr="$(ip addr show docker0 | grep -w inet | awk '{ print $2; }')"
  
  # Pour k8s 1.32, on utilise la ConfigMap kube-proxy
  kubectl -n kube-system get cm kube-proxy -o yaml | \
    sed -e "s|clusterCIDR:.*|clusterCIDR: \"${cluster_cidr}\"|g" \
        -e "s|mode:.*|mode: \"iptables\"|g" | \
    kubectl apply -f -
  
  # Redémarrer les pods kube-proxy
  kubectl -n kube-system delete pods -l k8s-app=kube-proxy --grace-period=0 --force 2>/dev/null || true
}

function dind::add-route {
  # Ajoute une route pour le réseau de service
  ip route add 10.96.0.0/12 dev eth0 2>/dev/null || true
}

function dind::wait-for-apiserver {
  echo -n "Attente du démarrage de l'API server"
  local url="https://localhost:6443/api"
  local n=120
  while true; do
    if curl -k -s "${url}" >&/dev/null; then
      break
    fi
    if ((--n == 0)); then
      echo ""
      echo "Erreur: timeout en attendant l'API server" >&2
      return 1
    fi
    echo -n "."
    sleep 1
  done
  echo " OK"
}

function dind::frob-cluster {
  echo "Configuration du cluster PWD..."
  
  # Modifier l'API server
  dind::frob-apiserver
  
  # Attendre que l'API server redémarre
  sleep 5
  dind::wait-for-apiserver
  
  # Configurer kube-proxy (si déjà installé)
  if kubectl -n kube-system get ds kube-proxy &>/dev/null; then
    dind::proxy-cidr-and-no-conntrack
  fi
}

# Générer un machine-id unique (requis pour Weave et autres CNI)
if [[ ! -f /etc/machine-id ]]; then
  rm -f /etc/machine-id
  systemd-machine-id-setup
fi

# Exécuter kubeadm avec les bons paramètres
if [[ "$1" == "init" ]] || [[ "$1" == "join" ]]; then
  # Pour init et join, toujours ignorer les preflight errors
  /usr/bin/kubeadm "$@" --ignore-preflight-errors=all
  exit_code=$?
  
  # Si init a réussi et ce n'est pas juste --help, configurer le cluster
  if [[ "$1" == "init" ]] && [[ $exit_code -eq 0 ]] && [[ ! "$*" =~ "--help" ]]; then
    dind::frob-cluster
  elif [[ "$1" == "join" ]] && [[ $exit_code -eq 0 ]]; then
    # Pour join, juste ajouter la route
    dind::add-route
  fi
  
  exit $exit_code
else
  # Pour les autres commandes (reset, token, etc.), exécuter normalement
  exec /usr/bin/kubeadm "$@"
fi
