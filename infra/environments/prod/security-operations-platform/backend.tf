# Configure a remote backend before this is used by a team.
#
# Example:
#
# terraform {
#   backend "s3" {
#     bucket         = "acme-prod-terraform-state"
#     key            = "eks/security-operations-platform/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "acme-prod-terraform-locks"
#     encrypt        = true
#   }
# }
