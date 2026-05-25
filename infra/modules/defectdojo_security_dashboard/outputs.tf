output "defectdojo_namespace" {
  value = kubernetes_namespace_v1.defectdojo.metadata[0].name
}

output "defectdojo_release_name" {
  value = helm_release.defectdojo.name
}

output "defectdojo_admin_username" {
  value = "admin"
}

output "defectdojo_admin_password" {
  value     = random_password.defectdojo_admin_password.result
  sensitive = true
}

output "defectdojo_port_forward_command" {
  value = "kubectl -n ${kubernetes_namespace_v1.defectdojo.metadata[0].name} port-forward svc/${helm_release.defectdojo.name}-django 8080:80"
}

output "defectdojo_local_url" {
  value = "http://localhost:8080"
}
