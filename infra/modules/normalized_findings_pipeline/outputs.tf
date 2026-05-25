output "security_findings_kms_key_arn" {
  value = aws_kms_key.security_findings_encryption_key.arn
}

output "raw_findings_archive_bucket_name" {
  value = aws_s3_bucket.raw_security_findings_archive.bucket
}

output "raw_findings_archive_bucket_arn" {
  value = aws_s3_bucket.raw_security_findings_archive.arn
}

output "normalized_findings_table_name" {
  value = aws_dynamodb_table.normalized_security_findings.name
}

output "normalized_findings_table_arn" {
  value = aws_dynamodb_table.normalized_security_findings.arn
}

output "finding_correlation_state_table_name" {
  value = aws_dynamodb_table.finding_correlation_state.name
}

output "finding_correlation_state_table_arn" {
  value = aws_dynamodb_table.finding_correlation_state.arn
}

output "security_findings_bus_name" {
  value = aws_cloudwatch_event_bus.security_findings.name
}

output "security_findings_bus_arn" {
  value = aws_cloudwatch_event_bus.security_findings.arn
}

output "normalized_findings_dlq_arn" {
  value = aws_sqs_queue.normalized_findings_dlq.arn
}
