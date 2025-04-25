#!/bin/bash
set -e

echo "Instalando Cilium mediante Helm..."
helm repo add cilium https://helm.cilium.io/
helm repo update

helm upgrade --install cilium cilium/cilium \
  --version 1.14.1 \
  --namespace kube-system \
  -f platform/kubernetes/cilium/values.yaml

echo "Esperando que Cilium esté listo..."
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=cilium-operator --timeout=120s
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=cilium --timeout=120s

echo "Verificando estado de Cilium..."
cilium_status=$(kubectl -n kube-system exec -ti ds/cilium -- cilium status)
echo "$cilium_status"

echo "Cilium instalado correctamente!"
