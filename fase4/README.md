# Fase 4 — Observabilidade (OTel Collector, Prometheus, Grafana, Loki)

| Documento | Conteúdo |
|-----------|----------|
| [01-setup-aws-do-zero.md](01-setup-aws-do-zero.md) | Conta AWS vazia → cluster com serviços, ArgoCD e observabilidade; como o ArgoCD lê o Git (seção 11); destroy |
| [02-arquitetura-otel.md](02-arquitetura-otel.md) | Arquitetura do OTel, pipelines e justificativa técnica (texto para o PDF) |
| [03-roteiro-demo-otel.md](03-roteiro-demo-otel.md) | Roteiro do trecho "Métricas, Logs e OTel" do vídeo e prints para o PDF |

## Onde está cada coisa

| Caminho | O quê |
|---------|-------|
| `gitops/bootstrap/apps/{observability-config,kube-prometheus-stack,loki,otel-gateway,otel-agent}.yaml` | Applications do ArgoCD da stack |
| `gitops/observability/values/` | values dos charts Helm |
| `gitops/observability/config/` | namespace, SecretProviderClasses, dashboard do Grafana |
| `*/telemetry.go`, `*/telemetry.py` | inicialização do SDK OpenTelemetry em cada serviço |
| `terraform/storage.tf` | add-on EBS CSI + StorageClass `gp3` (discos do Prometheus/Loki) |
| `terraform/modules/irsa`, `terraform/modules/secrets` | roles e secrets do otel-gateway e do Grafana |
| `scripts/build-push.sh` | build/push das imagens no ECR + troca da tag no GitOps |
| `scripts/bootstrap-app-data.sh` | tabelas nos RDS, `SERVICE_API_KEY` e flag de exemplo |
| `scripts/generate-traffic.sh` | tráfego para popular dashboard, Loki e APM |

## O que mudou em relação à entrega da Fase 3

Correções necessárias para subir numa conta nova:

- **EKS 1.30 → 1.35**: a 1.30 saiu do suporte estendido em 07/2026 e não pode mais ser criada.
- **Add-ons atualizados** para a 1.35: ALB Controller 3.6.3 (com a policy IAM
  correspondente), KEDA 2.21.0, Secrets Store CSI 1.6.2.
- **`tokenRequests` no CSI driver**: exigido pelo provider AWS atual; sem isso
  nenhum pod monta segredo do Secrets Manager.
- **Backend S3 sem bucket fixo**: o bucket é passado no `terraform init`.
- **`set-account.sh` genérico**: antes só trocava o ID da Fase 2 e não
  funcionava numa conta nova.
- **`repoURL` do ArgoCD** apontando para `vilsonbuenos/fiap-fase3`.
- **Redis com TLS** (`rediss://`): o ElastiCache tem criptografia em trânsito e
  auth token, então o texto puro é recusado.
- **`TARGETING_SERVICE_URL` sem `/targeting`**: o evaluation chamava
  `/rules/<flag>`, recebia 404 e ignorava a regra de segmentação sem avisar.
- **Destroy sem travar**: ECR com `force_delete` e secrets com
  `recovery_window_in_days = 0`, para poder recriar no mesmo dia.
- **3 nodes** em vez de 2, para caber a stack de observabilidade.
- **Acesso ao cluster para o grupo**: `eks_admin_principal_arns`.
- **`terraform.tfstate` removido do Git** (estava versionado na raiz) e `.gitignore` na raiz.

Fase 4 (observabilidade): tudo o que está na tabela "Onde está cada coisa".

## Pendências fora deste escopo

- O repositório não tem pipeline de CI/CD com DevSecOps (só o
  `gitops-bump.yaml`, que nenhum workflow chama). As imagens sobem pelo
  `scripts/build-push.sh`. Se o CI do grupo estiver em outro repositório, ele
  precisa usar Go ≥ 1.26 para compilar auth e evaluation.
- APM (painel do Datadog), alertas, PagerDuty/OpsGenie, ChatOps e self-healing
  são de outros membros. O que eles precisam do OTel está na seção 5 de
  [02-arquitetura-otel.md](02-arquitetura-otel.md).
