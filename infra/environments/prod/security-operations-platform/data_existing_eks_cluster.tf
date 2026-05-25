data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_eks_cluster" "target_cluster" {
  name = var.existing_eks_cluster_name
}

data "aws_eks_cluster_auth" "target_cluster" {
  name = var.existing_eks_cluster_name
}
