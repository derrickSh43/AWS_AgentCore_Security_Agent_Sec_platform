output "prowler_raw_findings_bucket_name" {
  value = aws_s3_bucket.prowler_raw_findings.bucket
}

output "prowler_cronjob_name" {
  value = kubernetes_cron_job_v1.prowler_posture_scan.metadata[0].name
}

output "prowler_namespace" {
  value = kubernetes_namespace_v1.prowler.metadata[0].name
}

output "prowler_normalizer_function_name" {
  value = aws_lambda_function.prowler_finding_normalizer.function_name
}
