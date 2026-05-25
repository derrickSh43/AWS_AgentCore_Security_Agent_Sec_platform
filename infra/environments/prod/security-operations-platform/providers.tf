provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Organization = var.organization_name
      Environment  = var.environment_name
      Platform     = var.platform_name
      ManagedBy    = "terraform"
      Repository   = var.configuration_repository_name
    }
  }
}

provider "awscc" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.target_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.target_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.target_cluster.token
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.target_cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.target_cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.target_cluster.token
  }
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}
