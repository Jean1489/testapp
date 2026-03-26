#!/bin/bash
# =============================================================================
# setup-kind.sh — Crea el cluster kind con ingress-nginx listo para testapp
# =============================================================================

set -e

CLUSTER_NAME="testapp"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     Setup kind cluster               ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Crear el cluster ───────────────────────────────────────────────────────
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo ">>> Cluster '${CLUSTER_NAME}' ya existe, saltando creación."
else
    echo ">>> Creando cluster kind '${CLUSTER_NAME}'..."
    cat <<EOF | kind create cluster --name ${CLUSTER_NAME} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 8090
        protocol: TCP
      - containerPort: 443
        hostPort: 8443
        protocol: TCP
EOF
    echo "    Cluster creado ✓"
fi

# ── 2. Instalar ingress-nginx ─────────────────────────────────────────────────
echo ""
echo ">>> Instalando ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "    Esperando que ingress-nginx esté listo..."
kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s

echo "    ingress-nginx listo ✓"

# ── 3. Crear namespace staging ───────────────────────────────────────────────
echo ""
echo ">>> Creando namespace 'staging'..."
kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -
echo "    Namespace listo ✓"

# ── 4. Agregar entrada en /etc/hosts ─────────────────────────────────────────
echo ""
echo ">>> Verificando /etc/hosts para testapp.local..."
if grep -q "testapp.local" /etc/hosts; then
    echo "    Ya existe en /etc/hosts ✓"
else
    echo "127.0.0.1 testapp.local" | sudo tee -a /etc/hosts
    echo "    Agregado a /etc/hosts ✓"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  kind cluster listo:                                         ║"
echo "║                                                              ║"
echo "║  Cluster    : testapp                                        ║"
echo "║  Ingress    : http://testapp.local:8090                      ║"
echo "║  Namespace  : staging                                        ║"
echo "║                                                              ║"
echo "║  Siguiente  : bash setup-jenkins.sh                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""