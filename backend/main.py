from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import os, socket, datetime

app = FastAPI(title="Deploy Test API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Simula variables que vendrían de secrets/configmap de K8s
APP_VERSION  = os.getenv("APP_VERSION",  "local")
NAMESPACE    = os.getenv("NAMESPACE",    "local")
ENVIRONMENT  = os.getenv("ENVIRONMENT", "local")
DB_HOST      = os.getenv("DB_HOST",     "not-set")   # vendría del Secret de Terraform
SECRET_KEY   = os.getenv("SECRET_KEY",  "not-set")   # vendría del Secret de Terraform

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/api/info")
def info():
    return {
        "version":     APP_VERSION,
        "namespace":   NAMESPACE,
        "environment": ENVIRONMENT,
        "hostname":    socket.gethostname(),
        "timestamp":   datetime.datetime.utcnow().isoformat() + "Z",
    }

@app.get("/api/config")
def config():
    """Muestra qué variables de entorno llegaron (sin exponer valores sensibles)"""
    return {
        "DB_HOST":    DB_HOST,
        "SECRET_KEY": "****" if SECRET_KEY != "not-set" else "not-set",
        "NAMESPACE":  NAMESPACE,
    }

@app.get("/api/deploy-check")
def deploy_check():
    """Endpoint para verificar que el tag desplegado es el esperado"""
    return {
        "image_tag":   APP_VERSION,
        "deployed_at": datetime.datetime.utcnow().isoformat() + "Z",
        "pod":         socket.gethostname(),
        "checks": {
            "env_vars_loaded": DB_HOST != "not-set",
            "namespace_set":   NAMESPACE != "local",
            "version_tagged":  APP_VERSION != "local",
        }
    }
