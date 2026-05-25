check "snyk_requires_github_and_snyk_inputs" {
  assert {
    condition = (
      !var.enable_snyk_pull_request_scanning ||
      (
        var.github_owner != null &&
        var.github_token != null &&
        var.github_repository_full_name != null &&
        var.github_repository_name != null &&
        var.github_webhook_secret != null &&
        var.snyk_token != null
      )
    )
    error_message = "enable_snyk_pull_request_scanning requires GitHub repository values, github_token, github_webhook_secret, and snyk_token."
  }
}

check "agentcore_requires_artifacts_and_dashboard" {
  assert {
    condition = (
      !var.enable_agentcore_reasoning_layer ||
      (
        var.enable_engineer_security_dashboard &&
        var.agentcore_reasoner_container_uri != null
      )
    )
    error_message = "enable_agentcore_reasoning_layer requires enable_engineer_security_dashboard and agentcore_reasoner_container_uri."
  }
}

check "security_agent_requires_targets" {
  assert {
    condition     = !var.enable_security_agent_pentesting || length(var.security_agent_verified_target_domains) > 0
    error_message = "enable_security_agent_pentesting requires at least one security_agent_verified_target_domains entry."
  }
}

check "argocd_requires_git_source" {
  assert {
    condition = (
      !var.enable_argocd_gitops_boundary ||
      (
        var.argocd_git_repository_url != null &&
        var.argocd_application_path != null
      )
    )
    error_message = "enable_argocd_gitops_boundary requires argocd_git_repository_url and argocd_application_path."
  }
}
