#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
REPOSITORY_NAME="${REPOSITORY_NAME:-acme-prod-eks-secops-agentcore-reasoner}"
IMAGE_TAG="${IMAGE_TAG:-$(date -u +%Y%m%d%H%M%S)}"
CONTEXT_DIR="infra/environments/prod/security-operations-platform/agentcore_reasoner_container"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REPOSITORY_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPOSITORY_NAME}"

aws ecr describe-repositories \
  --region "${AWS_REGION}" \
  --repository-names "${REPOSITORY_NAME}" >/dev/null 2>&1 || \
aws ecr create-repository \
  --region "${AWS_REGION}" \
  --repository-name "${REPOSITORY_NAME}" >/dev/null

aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

docker build -t "${REPOSITORY_URI}:${IMAGE_TAG}" "${CONTEXT_DIR}"
docker push "${REPOSITORY_URI}:${IMAGE_TAG}"

echo "${REPOSITORY_URI}:${IMAGE_TAG}"
