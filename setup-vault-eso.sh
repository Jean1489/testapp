#!/bin/bash
# =============================================================================
# setup-vault-eso.sh
# Instala External Secrets Operator en kind y verifica la conexión con Vault
# Ejecutar DESPUÉS de setup-kind.sh y de que docker-compose esté arriba
# =============================================================================

set -e

VAULT_ADDR="http://localhost:8200"
VAULT_TOKEN="root"
NAMESPACE="staging"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     Setup Vault + ESO                    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 1. Verificar que Vault está corriendo ─────────────────────────────────────
echo ">>> Verificando Vault..."
until curl -s "${VAULT_ADDR}/v1/sys/health" | grep -q '"initialized":true'; do
    echo "    Esperando que Vault arranque..."
    sleep 3
done
echo "    Vault OK ✓"
echo "    UI disponible en: http://localhost:8200 (token: root)"

# ── 2. Instalar ESO en el cluster kind ───────────────────────────────────────
echo ""
echo ">>> Instalando External Secrets Operator en kind..."

helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update

helm upgrade --install external-secrets \
    external-secrets/external-secrets \
    --namespace external-secrets \
    --create-namespace \
    --set installCRDs=true \
    --wait

echo "    ESO instalado ✓"

# ── 3. Verificar que los CRDs de ESO están disponibles ───────────────────────
echo ""
echo ">>> Verificando CRDs de ESO..."
kubectl get crd externalsecrets.external-secrets.io > /dev/null && echo "    ExternalSecret CRD OK ✓"
kubectl get crd secretstores.external-secrets.io    > /dev/null && echo "    SecretStore CRD OK ✓"

# ── 4. Obtener la IP del host accesible desde kind ────────────────────────────
echo ""
echo ">>> Detectando IP de Vault accesible desde kind..."

if [[ "$OSTYPE" == "darwin"* ]]; then
    # Mac: host.docker.internal siempre funciona
    HOST_IP="host.docker.internal"
else
    # Linux: obtener la IP del contenedor vault-local en la red testapp-net
    HOST_IP=$(docker inspect vault-local \
        --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
        2>/dev/null | head -1)

    if [ -z "$HOST_IP" ]; then
        # Fallback: IP del gateway de testapp-net
        HOST_IP=$(docker network inspect testapp-net \
            --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null)
    fi
fi

echo "    Vault IP para kind: ${HOST_IP}"
echo "    Vault accesible desde kind en: http://${HOST_IP}:8200"

# ── 5. Verificar que kind puede llegar a Vault ────────────────────────────────
echo ""
echo ">>> Verificando conectividad kind → Vault..."
kubectl run vault-test --rm -it --restart=Never \
    --image=curlimages/curl:latest \
    -- curl -s "http://${HOST_IP}:8200/v1/sys/health" 2>/dev/null | grep -q "initialized" \
    && echo "    kind puede conectar a Vault ✓" \
    || echo "    ⚠️  kind NO puede conectar a Vault. Ajusta vault_addr_from_cluster en variables.tf"

# ── 6. Seed inicial de Vault — crear los secrets de prueba ───────────────────
echo ""
echo ">>> Creando secrets de prueba en Vault..."

# Habilitar KV v2 si no existe
curl -s --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --request POST \
    --data '{"type":"kv-v2"}' \
    "${VAULT_ADDR}/v1/sys/mounts/secret" > /dev/null 2>&1 || true

# Escribir el secret del backend
curl -s --header "X-Vault-Token: ${VAULT_TOKEN}" \
    --request POST \
    --data "{
        \"data\": {
            \"DB_HOST\": \"db.${NAMESPACE}.internal\",
            \"SECRET_KEY\": \"$(openssl rand -hex 32)\",
            \"NAMESPACE\": \"${NAMESPACE}\"
        }
    }" \
    "${VAULT_ADDR}/v1/secret/data/${NAMESPACE}/backend" | grep -q "created_time" \
    && echo "    Secret '${NAMESPACE}/backend' creado en Vault ✓" \
    || echo "    ⚠️  Error creando el secret. Verifica que Vault esté corriendo."

# ── 7. Verificar que el secret se puede leer ─────────────────────────────────
echo ""
echo ">>> Verificando lectura del secret..."
RESULT=$(curl -s --header "X-Vault-Token: ${VAULT_TOKEN}" \
    "${VAULT_ADDR}/v1/secret/data/${NAMESPACE}/backend")

if echo "$RESULT" | grep -q "DB_HOST"; then
    echo "    Secret legible ✓"
    echo "    DB_HOST    : $(echo $RESULT | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['data']['DB_HOST'])")"
    echo "    SECRET_KEY : ****"
else
    echo "    ⚠️  No se pudo leer el secret"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Setup completado. Próximos pasos:                           ║"
echo "║                                                              ║"
echo "║  1. Actualiza vault_addr_from_cluster en variables.tf:       ║"
echo "║     http://${HOST_IP}:8200"
echo "║                                                              ║"
echo "║  2. Corre terraform apply para crear el SecretStore y        ║"
echo "║     ExternalSecret en el namespace staging                   ║"
echo "║                                                              ║"
echo "║  3. Verifica que ESO creó el Secret de K8s:                  ║"
echo "║     kubectl get secret backend-secrets -n staging            ║"
echo "║     kubectl get externalsecret -n staging                    ║"
echo "║                                                              ║"
echo "║  Vault UI → http://localhost:8200 (token: root)              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""