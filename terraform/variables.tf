variable "namespace" {
  type = string
}
variable "host" {
  type = string
}
variable "frontend_tag" {
  type    = string
  default = ""
}
variable "backend_tag" {
  type    = string
  default = ""
}
variable "deploy_folder" {
  type    = string
  default = "k8s/overlays/staging"
}
variable "deploy_branch" {
  type    = string
  default = "deploy"
}
variable "backend_secrets" {
  type      = map(string)
  sensitive = true
  default = {
    DB_HOST    = "db.staging.internal"
    SECRET_KEY = "staging-secret-key"
  }
}
variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}
