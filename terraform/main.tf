terraform {
  required_version = ">= 1.6"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

provider "kubernetes" {
  config_path = "/var/jenkins_home/.kube/config"
}

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app"                          = "testapp"
    }
  }
}

resource "kubernetes_secret" "backend" {
  metadata {
    name      = "backend-secrets"
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  type = "Opaque"
  data = var.backend_secrets
}

resource "kubernetes_config_map" "deploy_meta" {
  metadata {
    name      = "deploy-meta"
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  data = {
    frontend_tag  = var.frontend_tag
    backend_tag   = var.backend_tag
    host          = var.host
    deploy_folder = var.deploy_folder
    deploy_branch = var.deploy_branch
  }
}
