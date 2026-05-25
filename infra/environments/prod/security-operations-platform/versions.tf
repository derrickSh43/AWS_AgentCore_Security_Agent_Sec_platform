terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.46.0"
    }

    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.83.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.17.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.37.0"
    }

    github = {
      source  = "integrations/github"
      version = ">= 6.6.0"
    }

    time = {
      source  = "hashicorp/time"
      version = ">= 0.12.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.7.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.0"
    }
  }
}
