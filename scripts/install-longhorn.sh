#!/bin/bash
set -e

echo "Instalando Longhorn mediante Helm..."
kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -

helm repo add longhorn https://charts.longhorn.io
helm repo update

helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  -f platform/kubernetes/storage/values.yaml

echo "Esperando que Longhorn esté listo..."
kubectl -n longhorn-system wait --for=condition=Ready pod -l app=longhorn-manager --timeout=180s

echo "Configurando Longhorn como storage class por defecto..."
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

echo "Longhorn instalado correctamente!"
kubectl get storageclass
