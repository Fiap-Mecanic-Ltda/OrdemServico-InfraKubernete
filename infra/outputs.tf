output "ecr_repository_url" {
  value = aws_ecr_repository.os.repository_url
}

output "github_actions_role_arn" {
  description = "Vai no secret AWS_ROLE_ARN do OrdemServico-service e deste repositorio."
  value       = aws_iam_role.github_actions.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.os.arn
}

output "trafego_roteado" {
  description = "true quando o ALB ja manda as rotas de OS para este servico."
  value       = var.rotear_trafego_alb
}

output "ssm_path_prefix" {
  value = local.ssm_path_prefix
}
