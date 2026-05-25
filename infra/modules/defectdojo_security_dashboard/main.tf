resource "random_password" "defectdojo_admin_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "defectdojo_secret_key" {
  length  = 64
  special = false
}

resource "random_password" "defectdojo_credential_aes256_key" {
  length  = 32
  special = false
}

resource "random_password" "defectdojo_metrics_password" {
  length  = 24
  special = false
}

resource "random_password" "defectdojo_postgresql_password" {
  length  = 24
  special = false
}

resource "random_password" "defectdojo_valkey_password" {
  length  = 24
  special = false
}

resource "kubernetes_namespace_v1" "defectdojo" {
  metadata {
    name = var.defectdojo_namespace

    labels = {
      "app.kubernetes.io/name"       = "defectdojo"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "defectdojo" {
  name       = "${var.organization_name}-${var.environment_name}-${var.platform_name}-defectdojo"
  namespace  = kubernetes_namespace_v1.defectdojo.metadata[0].name
  repository = "https://raw.githubusercontent.com/DefectDojo/django-DefectDojo/helm-charts"
  chart      = "defectdojo"
  version    = var.defectdojo_chart_version

  timeout = 900

  values = [
    yamlencode({
      createSecret           = true
      createPostgresqlSecret = true
      createValkeySecret     = true

      host    = var.defectdojo_host
      siteUrl = "http://${var.defectdojo_host}"

      admin = {
        user                    = "admin"
        password                = random_password.defectdojo_admin_password.result
        firstName               = "Security"
        lastName                = "Admin"
        mail                    = "security-admin@example.com"
        secretKey               = random_password.defectdojo_secret_key.result
        credentialAes256Key     = random_password.defectdojo_credential_aes256_key.result
        metricsHttpAuthPassword = random_password.defectdojo_metrics_password.result
      }

      django = {
        ingress = {
          enabled     = false
          activateTLS = false
        }

        service = {
          type = var.defectdojo_service_type
        }

        mediaPersistentVolume = {
          enabled = true
          type    = "pvc"
          persistentVolumeClaim = {
            create      = true
            name        = "${var.organization_name}-${var.environment_name}-${var.platform_name}-defectdojo-media"
            size        = "10Gi"
            accessModes = ["ReadWriteOnce"]
          }
        }

        uwsgi = {
          resources = {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "512Mi"
            }
          }
        }

        nginx = {
          resources = {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }
      }

      celery = {
        beat = {
          resources = {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }

        worker = {
          replicas = 1
          resources = {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "512Mi"
            }
          }
        }
      }

      postgresql = {
        auth = {
          password = random_password.defectdojo_postgresql_password.result
        }
        primary = {
          persistence = {
            enabled = true
          }
        }
      }

      valkey = {
        auth = {
          password = random_password.defectdojo_valkey_password.result
        }
      }
    })
  ]
}
