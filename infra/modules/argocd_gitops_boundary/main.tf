resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.argocd_namespace

    labels = {
      "app.kubernetes.io/name"       = "argocd"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "${var.organization_name}-${var.environment_name}-${var.platform_name}-argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  values = [
    yamlencode({
      configs = {
        cm = {
          "application.instanceLabelKey" = "argocd.argoproj.io/instance"
        }

        rbac = {
          "policy.default" = "role:readonly"
          "policy.csv"     = <<-CSV
            p, role:engineer, applications, get, platform/*, allow
            p, role:engineer, applications, sync, platform/*, allow
            p, role:engineer, applications, action/*, platform/*, allow
          CSV
        }
      }

      controller = {
        metrics = {
          enabled = true
        }
      }

      server = {
        metrics = {
          enabled = true
        }
      }
    })
  ]
}

resource "kubernetes_manifest" "argocd_project_platform" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "platform"
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    }
    spec = {
      description = "Platform-owned applications for ${var.eks_cluster_name}."
      sourceRepos = [
        var.argocd_git_repository_url
      ]
      destinations = [
        {
          namespace = "*"
          server    = "https://kubernetes.default.svc"
        }
      ]
      clusterResourceWhitelist = [
        {
          group = "*"
          kind  = "*"
        }
      ]
      namespaceResourceWhitelist = [
        {
          group = "*"
          kind  = "*"
        }
      ]
    }
  }

  depends_on = [
    helm_release.argocd
  ]
}

resource "kubernetes_manifest" "argocd_application_approved_cluster_state" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "${var.organization_name}-${var.environment_name}-${var.platform_name}-approved-cluster-state"
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
      labels = {
        "security-approval-boundary" = "git-review-required"
      }
    }
    spec = {
      project = "platform"
      source = {
        repoURL        = var.argocd_git_repository_url
        targetRevision = var.argocd_git_revision
        path           = var.argocd_application_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = merge({
        syncOptions = [
          "CreateNamespace=true",
          "ApplyOutOfSyncOnly=true"
        ]
        },
        var.argocd_enable_automated_sync ? {
          automated = {
            prune    = false
            selfHeal = false
          }
        } : {}
      )
    }
  }

  depends_on = [
    kubernetes_manifest.argocd_project_platform
  ]
}
