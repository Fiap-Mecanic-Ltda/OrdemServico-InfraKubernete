# OrdemServico-InfraKubernete — Infra e deploy do OS Service

Terraform e manifestos Kubernetes do **OS Service** (microsserviço de Ordem de Serviço da Fase 4).
O cluster k3s, a VPC e o ALB interno são compartilhados e ficam no
[InfraKubernete](https://github.com/Fiap-Mecanic-Ltda/InfraKubernete); aqui fica só o que é do
serviço.

## Os três repositórios do OS Service

| # | Repositório | Conteúdo | CI/CD |
|---|---|---|---|
| 1 | [OrdemServico-service](https://github.com/Fiap-Mecanic-Ltda/OrdemServico-service) | API .NET 9 + Saga | build, testes, cobertura e push da imagem no ECR |
| 2 | **OrdemServico-InfraKubernete** (este) | ECR, role OIDC, target group/regra no ALB + manifestos `k8s/` | `terraform plan/apply` + deploy no k3s |
| 3 | [OrdemServico-InfraSGBD](https://github.com/Fiap-Mecanic-Ltda/OrdemServico-InfraSGBD) | RDS SQL Server próprio da OS | `terraform plan/apply` |

## Trava de publicação

Nada vai para a AWS enquanto a Repository Variable **`PUBLICAR_AWS`** não for `true`
(Settings → Secrets and variables → Actions → Variables). A mesma variável trava os três
repositórios do OS Service:

| Repositório | Com `PUBLICAR_AWS` desligada | Com `PUBLICAR_AWS=true` |
|---|---|---|
| OrdemServico-service | build, testes e build da imagem | + push no ECR e disparo do deploy |
| OrdemServico-InfraSGBD | só `terraform plan` | + `apply` na `main` |
| OrdemServico-InfraKubernete | `terraform plan` e render do kustomize | + `apply` e deploy na `main` |

Mesmo com a publicação ligada, o **tráfego continua no monolito** até a virada:
`rotear_trafego_alb = false` deixa o target group pronto mas sem a regra no listener.

## Como este stack conversa com os outros

```text
InfraKubernete (state prod/terraform.tfstate)
   │  outputs: vpc_id, ec2_instance_id, worker_asg_name, alb_listener_arn,
   │           github_oidc_provider_arn
   ▼  (terraform_remote_state, somente leitura)
OrdemServico-InfraKubernete (state prod/os-k8s/terraform.tfstate)
   │  cria: ECR mechanicltda-os, role mechanicltda-prod-os-github-actions,
   │        target group :8081 (server + ASG), regra do ALB (só na virada)
   ▼
deploy.yml → namespace ordem-servico no k3s
   lê do SSM: /mechanicltda/prod/os/db-connection-string (OrdemServico-InfraSGBD)
              /mechanicltda/prod/jwt-secret-key, newrelic-license-key, mensageria/* (InfraKubernete)
```

Entrada de tráfego depois da virada: API Gateway (`ANY /api/{proxy+}`, repositório Lambda) → VPC
Link → ALB interno → regra `/api/ordemservico*`, `/api/OrdemServico*`, `/api/ordem-servico/*` →
NodePort 8081 → pod do OS Service. O resto continua na ação padrão do listener (monolito, 8080).
O path pattern do ALB diferencia maiúsculas, por isso as duas grafias.

## Estrutura

```text
OrdemServico-InfraKubernete/
├── infra/
│   ├── versions.tf          # backend S3 (prod/os-k8s/terraform.tfstate) e provider
│   ├── data.tf              # remote state do InfraKubernete + locals
│   ├── variables.tf         # nomes, NodePort, rotear_trafego_alb, repositórios do OIDC
│   ├── ecr.tf               # repositório mechanicltda-os
│   ├── alb.tf               # target group, registro do server e do ASG, regra do listener
│   ├── github_oidc.tf       # role de CI/CD do serviço (ECR, SSM, S3 deploy/os/)
│   └── outputs.tf
├── k8s/
│   ├── base/                # Namespace, ConfigMap, Deployment, Service, HPA
│   └── overlays/prod/       # NodePort 8081 + imagePullSecrets do ECR
├── scripts/
│   ├── esperar-ssm.sh       # espera o Run Command terminar (mesmo do InfraKubernete)
│   └── instalar-refresh-ecr.sh  # timer que renova o ecr-creds do namespace a cada 6h
└── .github/workflows/
    ├── terraform.yml
    └── deploy.yml
```

## Configuração da aplicação no cluster

O ConfigMap (`k8s/base/configmap.yaml`) sobe o serviço com **`Saga__Habilitada=false`**: a API
funciona como na Fase 3 e nem conecta no RabbitMQ. Na virada, com Billing e Execução no ar e o
RabbitMQ instalado pelo InfraKubernete, basta trocar para `"true"` e fazer o deploy.
Cliente e veículo continuam no monolito, chamado dentro do cluster em
`http://mechanicltda-api.mechanicltda.svc.cluster.local:8080`.

O Secret `os-service-secrets` é montado pelo `deploy.yml` a partir do SSM a cada deploy; não há
segredo versionado.

## Secrets e variáveis do repositório

| Nome | Tipo | Uso |
|---|---|---|
| `PUBLICAR_AWS` | Variable | `true` libera `apply` e deploy (ver Trava de publicação) |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Secret | Chave do `terraform-deployer` para o `terraform.yml` |
| `AWS_ROLE_ARN` | Secret | Output `github_actions_role_arn`, usado pelo `deploy.yml` (OIDC) |

O Environment `production` precisa existir (apply e deploy).

## Primeira subida (ordem)

1. InfraKubernete com o suporte aos microsserviços aplicado (porta 8081, outputs novos e, para a
   Saga, `RABBITMQ_SEGREDO`).
2. OrdemServico-InfraSGBD (`apply`): banco e connection string no SSM.
3. Este repositório (`terraform.yml`): ECR, role e target group. Copie `github_actions_role_arn`
   para o secret `AWS_ROLE_ARN` daqui e do OrdemServico-service.
4. OrdemServico-service na `main`: publica a imagem e dispara o `deploy.yml` daqui.
5. Virada: `rotear_trafego_alb = true` aqui (e `Saga__Habilitada` quando os outros serviços
   estiverem no ar).

## Fluxo de trabalho no Git

Branch `feature/...` com Pull Request para `homologacao`, depois `homologacao` → `main` por Pull
Request. Em `homologacao` só roda `plan` e o render dos manifestos; `apply` e deploy só na `main`
e só com `PUBLICAR_AWS=true`.
