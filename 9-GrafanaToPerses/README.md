# Exercício 9: Dashboards com o Red Hat Build of Perses (Cluster Observability Operator)

> **Ainda não validado ao vivo** — escrito com base na documentação oficial (Red Hat Developer,
> docs do Cluster Observability Operator e docs de Observability do ACM), pendente de teste num
> hub com COO 1.5 + ACM 2.17 reais. O endpoint exato do `rbac-query-proxy` (porta/TLS) precisa
> ser confirmado ao vivo antes de rodar com uma turma.

Neste laboratório, você vai pegar um dashboard **real** que já roda hoje no ACM — o de vCPU dos
workers por managed cluster, feito com um `ConfigMap` do Grafana — e recriar o mesmo dashboard
com o **Perses**, os dois lado a lado, pra ver exatamente o que muda.

> **Por que fazer isso na mão, se ninguém pediu**: não existe (ainda) um anúncio formal de "o
> ACM vai descontinuar o Grafana". Mas tem evidência concreta de pra onde o vento sopra: no
> ACM 2.17, a feature de **right-sizing recommendations** (via MCOA — Multicluster
> Observability Add-on, o componente que roda nos managed clusters) já nasceu usando **Perses**
> como motor de visualização, não Grafana. Investimento em feature nova está indo pro Perses —
> o que não está claro ainda é o que acontece com dashboards customizados existentes
> (`grafana-custom-dashboard`) quando/se essa migração se completar. Fazer essa conversão na
> mão agora é treino pra um trabalho que muito provavelmente vai precisar ser feito de qualquer
> jeito, só ainda sem prazo definido pela Red Hat.

> **Ambiente de 15 alunos, tudo no hub**: os dados deste dashboard (`acm_managed_cluster_labels`,
> capacidade de CPU da frota inteira) só existem no **hub**, não em cada cluster individual —
> então este lab roda **contra o hub**, compartilhado pela turma. O COO/Perses é habilitado
> **uma vez, pelo instrutor**; cada aluno cria a própria versão do dashboard (Grafana e Perses)
> com o nome no final do recurso, pra não sobrescrever a dos colegas.

---

## Conceito Rápido

Hoje, um dashboard customizado no ACM é um `ConfigMap` rotulado `grafana-custom-dashboard:
"true"` no namespace `open-cluster-management-observability`, com o JSON do Grafana dentro —
exatamente como o dashboard de vCPU que este lab usa. O COO 1.5 GA o **Perses** como motor de
dashboard **suportado**, com integração nativa no console do OCP:

- **Zero context switching**: os dashboards aparecem em **Observe → Dashboards (Perses)**,
  dentro do próprio console — não é mais um link pra uma UI de Grafana separada.

  > **Dúvida em aberto**: hoje, no console do ACM (visão de Clusters), tem um botão/link
  > **Grafana** que leva pra fora, pro Grafana do ACM. Não achei confirmação de que esse ponto
  > de acesso vai virar um link pro Perses (ou sumir, com o dashboard passando a aparecer
  > embutido ali mesmo) — é o comportamento esperado dado o "zero context switching" que a Red
  > Hat descreve, mas não é algo que eu tenha visto documentado explicitamente pro console do
  > ACM especificamente (só pro console "puro" do OCP). Só dá pra confirmar isso olhando um ACM
  > 2.17 real.
- **Dashboard como objeto Kubernetes**: um `PersesDashboard` é um CR namespaced — versionável
  em Git, aplicável com `oc apply`, revisável em PR, igual qualquer outro recurso deste
  repositório (o `ConfigMap` do Grafana também é um objeto Kubernetes, mas o conteúdo dentro
  dele — o JSON — não é; no Perses, o dashboard inteiro é nativo).
- **Fontes de dado em duas camadas**: `PersesDatasource` (por namespace) e
  `PersesGlobalDatasource` (cluster-wide) — o Perses procura primeiro no namespace do
  dashboard, e cai pro global se não achar. Pra métricas de frota do ACM, o datasource certo é
  o `rbac-query-proxy` do ACM Observability, **não** o Thanos Querier comum da plataforma (ver
  aviso no Passo 2).

---

## Pré-requisitos

- Hub com **ACM Observability** habilitado e o dashboard de vCPU (ou outro `ConfigMap` de
  `grafana-custom-dashboard`) já existindo, pra comparação.
- **Cluster Observability Operator 1.5+** instalado no hub (via OperatorHub).
- `percli` instalado ([repositório do Perses](https://github.com/perses/perses)).
- Acesso ao namespace `open-cluster-management-observability` (pra aplicar seu `ConfigMap`) e
  permissão pra criar `PersesDashboard` no namespace `lab-perses-demo`.

---

## Passo 1: Habilitar o Perses no Console (instrutor, uma vez só)

```bash
oc apply -f 9-GrafanaToPerses/manifests/01-uiplugin-monitoring.yaml
oc apply -f 9-GrafanaToPerses/manifests/03-namespace.yaml
```

Confirme no console do hub: **Observe → Dashboards (Perses)** deve aparecer no menu lateral em
alguns minutos.

---

## Passo 2: Registrar a Fonte de Dados Global do ACM (instrutor, uma vez só)

```bash
oc apply -f 9-GrafanaToPerses/manifests/02-perses-global-datasource.yaml
```

> **Isso não é o Thanos Querier comum.** Pra puxar `acm_managed_cluster_labels` e métricas de
> toda a frota, o datasource é o **`rbac-query-proxy`** — o mesmo endpoint que o Grafana do ACM
> já usa hoje (`open-cluster-management-observability`). Usar o Thanos Querier padrão da
> plataforma só traria métricas do hub sozinho, sem o join com labels dos managed clusters.

---

## Passo 3: Sua Versão do Dashboard no Grafana ("hoje")

Copie `manifests/04-grafana-dashboard-configmap.yaml`, troque todo `<SEU_NOME>` pelo seu nome
(minúsculo, sem espaço — é `metadata.name` de um `ConfigMap`), e aplique:

```bash
oc apply -f 04-grafana-dashboard-configmap-<seu-nome>.yaml
```

Confirme no Grafana do ACM (rota `grafana` no mesmo namespace) que o dashboard **"ACM - Worker
Nodes vCPU Capacity (\<seu-nome\>)"** aparece, com dado real da frota.

---

## Passo 4: A Mesma Coisa no Perses

Converta o dashboard completo (6 painéis — `manifests/worker-vcpu-dashboard-grafana.json`, o
JSON puro por trás do `ConfigMap` do Passo 3) com o `percli`:

```bash
percli migrate -f 9-GrafanaToPerses/manifests/worker-vcpu-dashboard-grafana.json --online -o yaml \
  > worker-vcpu-perses-<seu-nome>.yaml
```

Abra o arquivo gerado e ajuste, antes de aplicar:

- `metadata.name` → algo com seu nome (ex.: `worker-vcpu-perses-<seu-nome>`)
- `metadata.namespace` → `lab-perses-demo`
- A referência de datasource → aponte pro `acm-rbac-query-proxy-datasource` do Passo 2 (o
  `percli` não sabe desse nome, ele converte pro datasource genérico do Grafana original)

```bash
oc apply -f worker-vcpu-perses-<seu-nome>.yaml
```

Abra **Observe → Dashboards (Perses)**, selecione o namespace `lab-perses-demo`, e compare o
seu dashboard Perses lado a lado com a versão Grafana do Passo 3 — mesma métrica, mesmo filtro
por cluster/vendor/cloud, dois motores de renderização.

> **Nem tudo converte perfeitamente**: variáveis de template (`$cluster`, `$vendor`, `$cloud`)
> e painéis do tipo `table` com `transformations` costumam ser os pontos que mais precisam de
> ajuste manual depois da conversão — confira painel por painel antes de considerar migrado de
> verdade.

---

## Passo 5: Editar Direto na UI (e Ver a Mudança Virar YAML)

No console, abra seu dashboard Perses e adicione/edite um painel pela interface. Confirme que a
mudança foi persistida de volta no objeto Kubernetes:

```bash
oc get persesdashboard worker-vcpu-perses-<seu-nome> -n lab-perses-demo -o yaml
```

Esse é o ponto central do lab: no Perses, a UI e o GitOps não são dois mundos separados — editar
na tela edita o CR, e o CR aplicado via Git edita a tela. No Grafana (Passo 3), a UI edita um
estado interno do Grafana; o `ConfigMap` só reflete o que foi aplicado originalmente, a menos
que você exporte e reaplique manualmente.

---

## Passo 6: Limpeza

**Individual** (cada aluno):

```bash
oc delete configmap grafana-dashboard-worker-vcpu-<seu-nome> -n open-cluster-management-observability
oc delete persesdashboard worker-vcpu-perses-<seu-nome> -n lab-perses-demo
```

**Compartilhado** (instrutor, só depois que todo mundo terminar):

```bash
oc delete namespace lab-perses-demo
oc delete -f 9-GrafanaToPerses/manifests/02-perses-global-datasource.yaml
oc delete -f 9-GrafanaToPerses/manifests/01-uiplugin-monitoring.yaml
```

---

## Referências

- [Visualize your cluster: Manage observability with Red Hat build of Perses — Red Hat Developer](https://developers.redhat.com/articles/2026/07/07/manage-observability-red-hat-build-perses)
- [Red Hat build of Perses with the cluster observability operator — Red Hat Developer](https://developers.redhat.com/articles/2026/04/02/red-hat-build-perses-cluster-observability-operator)
- [How we designed customizable dashboards in OpenShift — Red Hat Developer](https://developers.redhat.com/articles/2026/07/27/how-we-designed-customizable-dashboards-openshift)
- [Cluster Observability Operator release notes](https://docs.redhat.com/en/documentation/red_hat_openshift_cluster_observability_operator/1-latest/html/red_hat_openshift_cluster_observability_operator_release_notes/cluster-observability-operator-release-notes)
- [ACM Observability — Using Grafana dashboards](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.9/html/observability/using-grafana-dashboards)
