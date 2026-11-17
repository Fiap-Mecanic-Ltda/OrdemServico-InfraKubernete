# O cluster k3s, o ALB interno e o provider OIDC do GitHub pertencem ao stack
# compartilhado (repositorio InfraKubernete). Este stack so le os outputs do
# state remoto - nao trava nem grava nada no state de la.
data "terraform_remote_state" "kubernetes" {
  backend = "s3"

  config = {
    bucket = var.kubernetes_state_bucket
    key    = var.kubernetes_state_key
    region = var.aws_region
  }
}

data "aws_caller_identity" "current" {}

data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

locals {
  cluster = data.terraform_remote_state.kubernetes.outputs

  name_prefix = "${var.project_name}-${var.environment}-${var.service_name}"

  # Prefixo do proprio servico (connection string do OrdemServico-InfraSGBD) e o
  # prefixo compartilhado, de onde vem a chave JWT, o New Relic e a mensageria.
  ssm_path_prefix_compartilhado = "/${var.project_name}/${var.environment}"
  ssm_path_prefix               = "${local.ssm_path_prefix_compartilhado}/${var.service_name}"

  # Nome do server k3s (tag Name da EC2 no InfraKubernete). O deploy descobre o
  # instance id por ela, e a policy de SSM so libera instancias com essa tag.
  server_name_tag = "${var.project_name}-${var.environment}-api"

  state_bucket = var.kubernetes_state_bucket
}
