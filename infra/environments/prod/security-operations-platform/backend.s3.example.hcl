bucket         = "REPLACE_WITH_TERRAFORM_STATE_BUCKET"
key            = "eks/security-operations-platform/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "REPLACE_WITH_TERRAFORM_LOCK_TABLE"
encrypt        = true
