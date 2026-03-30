#!/bin/bash
# =============================================================================
# setup-jenkins.sh — Configura Jenkins local para el pipeline de pruebas
# Ejecutar UNA sola vez después de levantar docker-compose
# =============================================================================

set -e

JENKINS_URL="http://localhost:8088"
JENKINS_CLI="java -jar jenkins-cli.jar -s ${JENKINS_URL}"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     Setup Jenkins Local              ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Esperar a que Jenkins arranque ────────────────────────────────────────
echo ">>> Esperando que Jenkins esté listo..."
until curl -s -o /dev/null -w "%{http_code}" ${JENKINS_URL}/login | grep -q "200"; do
    sleep 5
    echo "    ... esperando"
done
echo "    Jenkins listo ✓"

# ── 2. Obtener la contraseña inicial ─────────────────────────────────────────
echo ""
echo ">>> Contraseña inicial de Jenkins:"
docker exec jenkins-local cat /var/jenkins_home/secrets/initialAdminPassword
echo ""
echo "    Abre http://localhost:8088 e ingresa esa contraseña"
echo "    Instala los plugins sugeridos"
echo "    Crea tu usuario admin"
echo ""

# ── 3. Instalar herramientas dentro del contenedor ───────────────────────────
echo ">>> Instalando kubectl y terraform dentro del contenedor Jenkins..."

docker exec jenkins-local bash -c '
    # kubectl
    if ! command -v kubectl &> /dev/null; then
        curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        mv kubectl /usr/local/bin/
        echo "kubectl instalado ✓"
    else
        echo "kubectl ya existe ✓"
    fi

    # terraform
    if ! command -v terraform &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq unzip
        curl -sLo terraform.zip https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip
        unzip -q terraform.zip
        mv terraform /usr/local/bin/
        rm terraform.zip
        echo "terraform instalado ✓"
    else
        echo "terraform ya existe ✓"
    fi

    # kustomize
    if ! command -v kustomize &> /dev/null; then
        curl -sLo kustomize.tar.gz https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.3.0/kustomize_v5.3.0_linux_amd64.tar.gz
        tar -xzf kustomize.tar.gz
        mv kustomize /usr/local/bin/
        rm kustomize.tar.gz
        echo "kustomize instalado ✓"
    else
        echo "kustomize ya existe ✓"
    fi

    # docker cli
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | sh
        echo "docker instalado ✓"
    else
        echo "docker ya existe ✓"
    fi
'

# ── 4. Dar acceso al kubeconfig del kind cluster ──────────────────────────────
echo ""
echo ">>> Generando kubeconfigs del kind cluster..."

KIND_CLUSTER_NAME="testapp"
KIND_IP=$(docker inspect "testapp-control-plane" --format '{{.NetworkSettings.Networks.kind.IPAddress}}')

# Puerto que kind expone en localhost del host (lo lee del kubeconfig original)
kind export kubeconfig --name "${KIND_CLUSTER_NAME}" --kubeconfig /tmp/kind-config-host

# -- kubeconfig para el HOST (127.0.0.1 con el puerto real) --
# kind ya genera este con la dirección correcta para localhost
cp /tmp/kind-config-host ~/.kube/config
echo "    kubeconfig host actualizado ✓ (127.0.0.1)"

# -- kubeconfig para JENKINS (IP interna de la red kind) --
cp /tmp/kind-config-host /tmp/kind-config-jenkins

# Reemplaza solo el server: line, no todos los puertos del archivo
sed -i "s|server: https://127.0.0.1:[0-9]*|server: https://${KIND_IP}:6443|g" /tmp/kind-config-jenkins

mkdir -p ~/.kube
cp /tmp/kind-config-jenkins ~/.kube/config-jenkins

rm /tmp/kind-config-host /tmp/kind-config-jenkins
echo "    kubeconfig jenkins actualizado ✓ (${KIND_IP}:6443)"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Setup completado. Próximos pasos:                           ║"
echo "║                                                              ║"
echo "║  1. Abre http://localhost:8088                               ║"
echo "║  2. Instala plugins: Git, Pipeline, Credentials Binding      ║"
echo "║  3. Crea credencial 'github-credentials' (user + token)      ║"
echo "║  4. Crea el pipeline apuntando al Jenkinsfile del repo       ║"
echo "║  5. Cambia REPOSITORY en el Jenkinsfile con tu repo          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""