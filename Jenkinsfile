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
        DATE          = sh(script: 'date "+%Y-%m-%d-%H-%M-%S"', returnStdout: true).trim()
        FRONTEND_TAG  = "${params.FRONTEND_TAG}"
        BACKEND_TAG   = "${params.BACKEND_TAG}"
        HOST          = "${params.HOST}"
        NAMESPACE     = "${params.NAMESPACE}"
        DEPLOY_FOLDER = "${params.DEPLOY_FOLDER}"
        DEPLOY_BRANCH = "${params.DEPLOY_BRANCH}"
        KUBECONFIG    = "/root/.kube/config"
    }

    stages {
        // ── 1. VALIDACIÓN ─────────────────────────────────────────────────────
        stage('Validate Parameters') {
            steps {
                script {
                    if (!params.FRONTEND_TAG?.trim() && !params.BACKEND_TAG?.trim()) {
                        error("Debes proveer al menos FRONTEND_TAG o BACKEND_TAG.")
                    }
                }
            }
        }

        // ── 2. PARALELISMO (Aquí estaba el detalle de las llaves) ─────────────
        stage('Infrastructure & Source') {
            parallel {
                stage('Terraform Apply') {
                    steps {
                        sh '''
                            cd terraform
                            terraform init -input=false
                            terraform apply -input=false -auto-approve \
                                -var="namespace=${NAMESPACE}" \
                                -var="host=${HOST}" \
                                -var="frontend_tag=${FRONTEND_TAG}" \
                                -var="backend_tag=${BACKEND_TAG}"
                        '''
                    }
                }

                stage('Clone Deploy Branch') {
                    steps {
                        withCredentials([usernamePassword(credentialsId: 'github-credentials', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                            sh '''
                                git config --global user.email "yanke1489@gmail.com"
                                git config --global user.name "jenkins-local"
                                rm -rf testapp-deploy
                                git clone -b ${DEPLOY_BRANCH} --depth 5 https://${GIT_USERNAME}:${GIT_PASSWORD}@${REPOSITORY} testapp-deploy
                            '''
                        }
                    }
                }
            } // Cierre de parallel
        } // Cierre de stage 'Infrastructure & Source'

        // ── 3. ACTUALIZAR MANIFESTS ───────────────────────────────────────────
        stage('Update Manifests') {
            steps {
                script {
                    def imageEdits = []
                    if (params.FRONTEND_TAG?.trim()) {
                        imageEdits << "kustomize edit set image localhost/frontend=localhost/frontend:${FRONTEND_TAG}"
                    }
                    if (params.BACKEND_TAG?.trim()) {
                        imageEdits << "kustomize edit set image localhost/backend=localhost/backend:${BACKEND_TAG}"
                    }

                    withEnv(["EDITS=${imageEdits.join('\n')}"]) {
                        sh '''
                            cd testapp-deploy/${DEPLOY_FOLDER}
                            eval "$EDITS"
                            kustomize edit set namespace ${NAMESPACE}
                            sed -i "s|PLACEHOLDER_HOST|${HOST}|g" patch-ingress.yaml
                        '''
                    }
                }
            }
        }

        // ── 4. COMMIT & PUSH ──────────────────────────────────────────────────
        stage('Commit & Push') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-credentials', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                    sh '''
                        cd testapp-deploy/${DEPLOY_FOLDER}
                        git add .
                        if ! git diff --cached --quiet; then
                            git commit -m "Deploy ${DATE} - ${NAMESPACE}"
                            git push https://${GIT_USERNAME}:${GIT_PASSWORD}@${REPOSITORY} ${DEPLOY_BRANCH}
                        fi
                    '''
                }
            }
        }

        // ── 5. DESPLIEGUE FINAL ───────────────────────────────────────────────
        stage('Kubectl Apply') {
            steps {
                sh '''
                    kubectl apply -k testapp-deploy/${DEPLOY_FOLDER}
                '''
            }
        }
    } // Cierre de stages

    post {
        always {
            sh "rm -rf testapp-deploy"
        }
    }
} // Cierre de pipeline