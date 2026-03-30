pipeline {
    agent any

    parameters {
        string(name: 'FRONTEND_TAG',  defaultValue: '', description: 'Tag imagen frontend. Vacío = no actualizar.')
        string(name: 'BACKEND_TAG',   defaultValue: '', description: 'Tag imagen backend. Vacío = no actualizar.')
        string(name: 'HOST',          defaultValue: 'testapp.local', description: 'Host del Ingress')
        string(name: 'NAMESPACE',     defaultValue: 'staging', description: 'Kubernetes namespace')
        string(name: 'DEPLOY_FOLDER', defaultValue: 'k8s/overlays/staging', description: 'Path al overlay Kustomize en la rama deploy')
        string(name: 'DEPLOY_BRANCH', defaultValue: 'deploy', description: 'Rama git con los manifests')
    }

    environment {
        REPOSITORY    = "github.com/Jean1489/testapp.git"
        DATE          = sh(script: 'TZ="America/Bogota" date "+%Y-%m-%d-%H-%M-%S"', returnStdout: true).trim()
        FRONTEND_TAG  = "${params.FRONTEND_TAG}"
        BACKEND_TAG   = "${params.BACKEND_TAG}"
        HOST          = "${params.HOST}"
        NAMESPACE     = "${params.NAMESPACE}"
        DEPLOY_FOLDER = "${params.DEPLOY_FOLDER}"
        DEPLOY_BRANCH = "${params.DEPLOY_BRANCH}"
        KUBECONFIG    = "/root/.kube/config"
    }

    stages {

        // ── 1. Validar params ─────────────────────────────────────────────────
        stage('Validate Parameters') {
            steps {
                script {
                    if (!params.FRONTEND_TAG?.trim() && !params.BACKEND_TAG?.trim()) {
                        error("Debes proveer al menos FRONTEND_TAG o BACKEND_TAG.")
                    }
                    ['HOST', 'NAMESPACE', 'DEPLOY_FOLDER', 'DEPLOY_BRANCH'].each { key ->
                        if (!params[key]?.trim()) {
                            error("El parámetro '${key}' es obligatorio.")
                        }
                    }

                    def frontendMsg = params.FRONTEND_TAG?.trim() ? "actualizar a ${FRONTEND_TAG}" : "sin cambios"
                    def backendMsg  = params.BACKEND_TAG?.trim()  ? "actualizar a ${BACKEND_TAG}"  : "sin cambios"

                    echo """
╔══════════════════════════════════════════════╗
║           Deploy Configuration               ║
╠══════════════════════════════════════════════╣
║ FRONTEND_TAG  : ${frontendMsg.padRight(28)}║
║ BACKEND_TAG   : ${backendMsg.padRight(28)}║
║ HOST          : ${HOST.padRight(28)}║
║ NAMESPACE     : ${NAMESPACE.padRight(28)}║
║ DEPLOY_FOLDER : ${DEPLOY_FOLDER.padRight(28)}║
║ DEPLOY_BRANCH : ${DEPLOY_BRANCH.padRight(28)}║
╚══════════════════════════════════════════════╝
                    """.stripIndent()
                }
            }
        }

        // ── 2. Clone en paralelo (Terraform eliminado) ────────────────────────
        stage('Clone Deploy Branch') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-credentials', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                    sh """
                        if ! command -v kustomize &> /dev/null; then
                            curl -sLo kustomize.tar.gz https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.3.0/kustomize_v5.3.0_linux_amd64.tar.gz
                            tar -xzf kustomize.tar.gz
                            mv kustomize /usr/local/bin/
                            rm kustomize.tar.gz
                        fi

                        git config --global user.email "jenkins@local.com"
                        git config --global user.name "jenkins-local"

                        rm -rf testapp-deploy
                        git clone -b ${DEPLOY_BRANCH} --depth 5 \
                            https://${GIT_USERNAME}:${GIT_PASSWORD}@${REPOSITORY} \
                            testapp-deploy
                    """
                }
            }
        }

        // ── 3. Actualizar manifests ───────────────────────────────────────────
        stage('Update Manifests') {
            steps {
                script {
                    def frontendTag = params.FRONTEND_TAG?.trim()
                    def backendTag  = params.BACKEND_TAG?.trim()

                    def imageEdits = []
                    if (frontendTag) {
                        imageEdits << "kustomize edit set image localhost/frontend=localhost:5001/frontend:${frontendTag}"
                    }
                    if (backendTag) {
                        imageEdits << "kustomize edit set image localhost/backend=localhost:5001/backend:${backendTag}"
                    }

                    def imageEditsStr = imageEdits.join('\n')

                    sh """
                        cd testapp-deploy/${DEPLOY_FOLDER}

                        ${imageEditsStr}

                        kustomize edit set namespace ${NAMESPACE}
                        sed -i "s|PLACEHOLDER_HOST|${HOST}|g" patch-ingress.yaml

                        echo ">>> kustomization.yaml actualizado:"
                        cat kustomization.yaml
                    """
                }
            }
        }

        // ── 4. Commit & Push ──────────────────────────────────────────────────
        stage('Commit & Push') {
            steps {
                script {
                    def parts = []
                    if (params.FRONTEND_TAG?.trim()) parts << "frontend:${FRONTEND_TAG}"
                    if (params.BACKEND_TAG?.trim())  parts << "backend:${BACKEND_TAG}"
                    def commitMsg = "Trigger Deploy - ${parts.join(', ')} → ${NAMESPACE} - ${DATE}"

                    withCredentials([usernamePassword(credentialsId: 'github-credentials', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                        sh """
                            cd testapp-deploy/${DEPLOY_FOLDER}

                            git add kustomization.yaml patch-ingress.yaml

                            if git diff --cached --quiet; then
                                echo "Sin cambios en los manifests — nada que commitear."
                            else
                                git commit -m "${commitMsg}"
                                git push https://${GIT_USERNAME}:${GIT_PASSWORD}@${REPOSITORY} ${DEPLOY_BRANCH}
                                echo ">>> Push OK a '${DEPLOY_BRANCH}'"
                            fi
                        """
                    }
                }
            }
        }

        // ── 5. Aplicar en kind ────────────────────────────────────────────────
        stage('Kubectl Apply') {
            steps {
                sh """
                    kubectl cluster-info

                    kubectl apply -k testapp-deploy/${DEPLOY_FOLDER}

                    echo ">>> Esperando rollout..."
                    kubectl rollout status deployment/frontend -n ${NAMESPACE} --timeout=120s
                    kubectl rollout status deployment/backend  -n ${NAMESPACE} --timeout=120s

                    echo ""
                    echo ">>> Pods:"
                    kubectl get pods -n ${NAMESPACE}

                    echo ""
                    echo ">>> Estado del ExternalSecret:"
                    kubectl get externalsecret backend-secrets -n ${NAMESPACE}

                    echo ""
                    echo ">>> Secret creado por ESO:"
                    kubectl get secret backend-secrets -n ${NAMESPACE} && echo "Secret OK ✓" || echo "⚠️  ESO aún sincronizando..."
                """
            }
        }
    }

    post {
        success {
            script {
                def parts = []
                if (params.FRONTEND_TAG?.trim()) parts << "frontend:${FRONTEND_TAG}"
                if (params.BACKEND_TAG?.trim())  parts << "backend:${BACKEND_TAG}"
                echo "✅  Deploy [${parts.join(', ')}] en '${NAMESPACE}' completado."
            }
        }
        failure {
            echo "❌  Deploy fallido. Revisa los logs."
        }
        cleanup {
            sh "rm -rf testapp-deploy"
        }
    }
}