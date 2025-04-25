#!/bin/bash
set -e

echo "Creando cluster K3d..."
k3d cluster create --config local-dev/k3d/cluster.yaml

echo "Esperando que el cluster esté listo..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "Configurando kubectl y contexto..."
kubectl config use-context k3d-multi-cloud-cluster

echo "Cluster K3d listo y configurado!"
kubectl get nodes
