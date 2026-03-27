#!/bin/bash
# =============================================================================
# setup-kind.sh — Crea el cluster kind con ingress-nginx listo para testapp
# =============================================================================

set -e

CLUSTER_NAME="testapp"
REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5001"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     Setup kind cluster               ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Levantar el registry local ────────────────────────────────────────────
echo ">>> Configurando registry local..."
if docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
    echo "    Registry '${REGISTRY_NAME}' ya existe, saltando creación."
else
    docker run -d --restart=always \
        -p "${REGISTRY_PORT}:5000" \
        --name "${REGISTRY_NAME}" \
        registry:2
    echo "    Registry creado en localhost:${REGISTRY_PORT} ✓"
fi

# ── 2. Crear el cluster ───────────────────────────────────────────────────────
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo ">>> Cluster '${CLUSTER_NAME}' ya existe, saltando creación."
else
    echo ">>> Creando cluster kind '${CLUSTER_NAME}'..."
    cat <<EOF | kind create cluster --name ${CLUSTER_NAME} --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REGISTRY_PORT}"]
      endpoint = ["http://${REGISTRY_NAME}:5000"]
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

# ── Generar kubeconfig para uso desde contenedores Docker ────────────────────
echo ""
echo ">>> Generando kubeconfig para Jenkins..."
kind get kubeconfig --name "${CLUSTER_NAME}" \
  | sed "s/127.0.0.1:[0-9]*/testapp-control-plane:6443/" \
  > ~/.kube/config-jenkins

echo "    Kubeconfig para Jenkins en ~/.kube/config-jenkins ✓"

# ── 3. Conectar registry a la red de kind ────────────────────────────────────
echo ""
echo ">>> Conectando registry a la red 'kind'..."
if docker network inspect kind | grep -q "${REGISTRY_NAME}"; then
    echo "    Registry ya está en la red kind ✓"
else
    docker network connect kind "${REGISTRY_NAME}"
    echo "    Registry conectado ✓"
fi

# ── 4. Publicar ConfigMap del registry (buena práctica para herramientas) ────
echo ""
echo ">>> Aplicando ConfigMap de registry..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHostingV1: |
    host: "localhost:${REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF
echo "    ConfigMap aplicado ✓"

# ── 5. Instalar ingress-nginx ─────────────────────────────────────────────────
echo ""
echo ">>> Instalando ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "    Esperando que ingress-nginx esté listo..."
kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s

echo "    ingress-nginx listo ✓"

# ── 6. Crear namespace staging ───────────────────────────────────────────────
echo ""
echo ">>> Creando namespace 'staging'..."
kubectl create namespace staging --dry-run=client -o yaml | kubectl apply -f -
echo "    Namespace listo ✓"

# ── 7. Agregar entrada en /etc/hosts ─────────────────────────────────────────
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
echo "║  Registry   : localhost:5001                                 ║"
echo "║  Ingress    : http://testapp.local:8090                      ║"
echo "║  Namespace  : staging                                        ║"
echo "║                                                              ║"
echo "║  Siguiente  : bash setup-jenkins.sh                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""