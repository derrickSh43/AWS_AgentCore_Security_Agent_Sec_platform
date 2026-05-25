output "argocd_namespace" {
  value = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "argocd_application_name" {
  value = kubernetes_manifest.argocd_application_approved_cluster_state.manifest.metadata.name
}

output "argocd_automated_sync_enabled" {
  value = var.argocd_enable_automated_sync
}
