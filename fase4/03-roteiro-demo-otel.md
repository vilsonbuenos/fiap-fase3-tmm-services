# 03 — Roteiro do vídeo: Métricas, Logs e OTel (~5 min)

Trecho do enunciado: *"Abra o Grafana. Mostre seu dashboard customizado
exibindo as métricas. Busque logs no Loki. Explique rapidamente como o OTel
Collector está roteando esses dados."*

## Antes de gravar (10 min antes)

```bash
export AWS_PROFILE=fiap-fase4 AWS_REGION=us-east-2

# Terminal 1 — tráfego contínuo (os painéis precisam de dados dos últimos 5 min)
bash scripts/generate-traffic.sh 20

# Terminal 2 — Grafana
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80

# Senha do Grafana
aws secretsmanager get-secret-value --secret-id observability/GRAFANA_ADMIN \
  --query SecretString --output text
```

Deixe abertos, nesta ordem, em abas:

1. Grafana → dashboard **ToggleMaster — Saúde do Ecossistema** (`now-30m`, refresh 10s)
2. Grafana → **Explore** com o datasource Loki
3. VS Code com `gitops/observability/values/otel-gateway.yaml`, rolado até `service.pipelines`
4. Este arquivo (o diagrama em [02-arquitetura-otel.md](02-arquitetura-otel.md) no preview do VS Code)

Para ter erro na tela, ~2 min antes de gravar (com o `generate-traffic.sh` rodando):

```bash
kubectl -n flag-service scale deploy/flag-service --replicas=0
```

Sem o flag-service, as chamadas que não estão no cache do Redis (o script
também consulta uma flag inexistente, que nunca é cacheada) retornam **502** no
evaluation-service. O span vira erro e aparece no painel de taxa de erro, e a
linha `Erro ao avaliar flag` aparece no Loki com nível `error`. Em segundos o
ArgoCD (selfHeal) volta o Deployment para 1 réplica sozinho. Se não voltar:
`kubectl -n flag-service scale deploy/flag-service --replicas=1`.

> Isso só popula os painéis. O incidente com alerta, PagerDuty e self-healing é
> o roteiro de outro membro do grupo.

---

## 0:00–0:30 — Contexto

**Tela:** dashboard, rolado no topo.

**Fale:**

> No incidente do enunciado, o evaluation-service falhou em silêncio e a causa
> levou horas para aparecer nos logs espalhados pelos pods. Agora toda a
> telemetria passa por um ponto central, o OpenTelemetry Collector, e chega
> padronizada no Grafana. Este é o dashboard que criamos para a saúde do
> ecossistema inteiro.

## 0:30–2:00 — Dashboard

Aponte cada linha do dashboard:

1. **Cluster EKS** — nodes prontos, CPU e memória do cluster, pods, restarts.
   CPU e memória por namespace e réplicas por microsserviço (onde o HPA/KEDA
   aparece escalando).
   > Isso vem do scrape nativo do Prometheus: node-exporter, cAdvisor e kube-state-metrics.
2. **Microsserviços** — requisições por segundo, taxa de erro e latência p95 dos
   cinco serviços, chamadas entre serviços, fila SQS (enviados x processados) e
   cache hit/miss do Redis.
   > Essas métricas não vêm de scrape. Os serviços mandam spans para o
   > Collector, e o Collector gera taxa, erro e latência a partir deles, com os
   > mesmos nomes para Go e Python. O cache hit/miss é uma métrica de negócio
   > criada no código Go com o SDK do OpenTelemetry.
3. **OTel Collector** — itens recebidos por receiver e exportados por destino.
   > Aqui dá para ver o roteamento acontecendo: spans saindo para o Datadog,
   > métricas para o Prometheus via remote write, logs para o Loki. E o
   > contador de falhas de exportação, que deve ficar em zero.
4. **Logs** — volume e linhas de erro por serviço, e os logs em tempo real.

Troque a variável **Serviço** para `evaluation-service` e mostre os painéis filtrando.

## 2:00–3:30 — Loki

**Tela:** Explore → Loki. Rode uma query por vez:

```logql
{service_name="evaluation-service"}
```

> Todos os logs de todos os pods do evaluation, num lugar só. Os labels
> namespace, pod e deployment foram adicionados pelo Collector.

```logql
{k8s_namespace_name=~"auth-service|flag-service|targeting-service|evaluation-service|analytics-service"} | detected_level="error"
```

> Só os erros dos cinco serviços. Os serviços logam em texto puro; o Collector
> deduz o nível e grava como severidade.

Expanda uma linha que tenha `trace_id=`. Copie o valor e rode:

```logql
{k8s_namespace_name=~".+"} | trace_id="<cole aqui>"
```

> Esta é a correlação: o mesmo trace_id aparece nos logs do evaluation, do flag,
> do targeting e do auth. É a mesma requisição que vamos ver como trace
> distribuído no Datadog. Com isso, a causa raiz que levou quatro horas agora é
> uma busca.

## 3:30–4:45 — Como o Collector roteia

**Tela:** diagrama de [02-arquitetura-otel.md](02-arquitetura-otel.md), depois o
`otel-gateway.yaml` na parte `service.pipelines`.

```bash
kubectl -n observability get pods -o wide | grep otel
```

**Fale:**

> São dois Collectors. O otel-agent roda um por node e lê os logs de todos os
> containers. O otel-gateway é a peça central: recebe OTLP dos cinco serviços e
> dos agents.
>
> No gateway, cada sinal tem um pipeline. Traces passam por memory limiter,
> enriquecimento com metadados do Kubernetes e batch, e saem para o Datadog. No
> caminho, dois conectores: o span_metrics gera as métricas de taxa, erro e
> latência que vimos no dashboard, e o connector do Datadog calcula as
> estatísticas do APM para o Service Map. Métricas vão para o Prometheus por
> remote write. Logs vão para o Loki em OTLP nativo.
>
> O código dos serviços não sabe que existe Prometheus, Loki ou Datadog. Ele só
> fala OTLP com o Collector. Trocar de backend é trocar um exporter neste arquivo.

## 4:45–5:00 — Fecho

> Tudo isso está no GitOps: os charts do Prometheus, Loki e Collector são
> Applications do ArgoCD, com os values e o dashboard versionados no repositório.

---

## Evidências para o PDF

| Print | Onde |
|-------|------|
| Dashboard completo (obrigatório) | Grafana → dashboard, `now-30m`, com tráfego. Use *Share → Export → Save to file* ou capture em duas partes |
| Logs no Loki filtrados por `trace_id` | Explore, terceira query |
| Painel "Exportado por destino" | dashboard, linha OTel Collector |
| Applications do ArgoCD Synced/Healthy | `kubectl -n argocd get applications` ou a UI |
| Pods do Collector | `kubectl -n observability get pods -o wide` |

## Justificativa técnica (texto pronto)

Use o resumo do topo de [02-arquitetura-otel.md](02-arquitetura-otel.md).
