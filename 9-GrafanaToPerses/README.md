# Exercício 9: Dashboards com o Red Hat Build of Perses — Dois Caminhos

> **Ainda não validado ao vivo** — escrito com base na documentação oficial (Red Hat Developer,
> docs do Cluster Observability Operator, e o guia oficial *Red Hat Advanced Cluster Management
> for Kubernetes 2.17 — Observability*), pendente de teste num cluster com COO 1.5 (Parte 1) e
> num hub ACM 2.17 real (Parte 2). Pontos específicos a confirmar: o schema exato do
> `PersesDashboard` (Parte 1) e o endpoint do `thanos-querier` local (porta/TLS); e, na Parte 2,
> se o patch do MCO realmente expõe o dashboard `ACM Clusters Overview` como descrito no guia.

Existem **dois jeitos diferentes** de ter Perses funcionando no console do OCP em cima do ACM, e
eles não são a mesma coisa:

- **Parte 1 — Caminho genérico do Cluster Observability Operator**: cada aluno cria os CRs
  (`UIPlugin`, `PersesGlobalDatasource`, `PersesDashboard`) no **próprio managed cluster** — sem
  depender do hub nem de dado de frota. Funciona em qualquer cluster OpenShift com o COO
  instalado, ACM ou não. É o caminho documentado nos artigos do Red Hat Developer e na doc
  genérica do COO.
- **Parte 2 — Caminho oficial do ACM: Multicluster Observability Add-on (MCOA)**: o próprio ACM
  2.17 tem uma integração nativa de Perses, documentada no guia oficial de Observability do ACM
  (seção 1.11), com dashboards de frota já prontos (`ACM Clusters Overview`). É **Technology
  Preview** e liga por um mecanismo bem diferente — troca o pipeline inteiro de coleta de
  métricas do managed cluster, não é só "ligar uma UI". Fica pré-configurada no hub pelo
  instrutor antes da aula — a lição da Parte 2 é explorar o que já está lá, não ligar você mesmo.

> **Por que fazer isso, se ninguém pediu**: não existe (ainda) um anúncio formal de "o ACM vai
> descontinuar o Grafana". Mas tem evidência concreta de pra onde o vento sopra: no ACM 2.17, a
> feature de **right-sizing recommendations** (via MCOA) já nasceu usando **Perses** como motor
> de visualização, não Grafana. Investimento em feature nova está indo pro Perses — treinar com
> ele agora é se antecipar a um trabalho que muito provavelmente vai precisar ser feito de
> qualquer jeito, só ainda sem prazo definido pela Red Hat.

> **Ambiente de 15 alunos, cada um no próprio cluster (Parte 1)**: diferente da versão anterior
> deste lab (que usava um dashboard real de frota, só disponível no hub), a Parte 1 agora roda
> **isolada, no managed cluster de cada aluno** — sem hub compartilhado, sem risco de um aluno
> sobrescrever o recurso do outro, sem nome de aluno no `metadata.name`. O exemplo é
> deliberadamente simples (CPU/memória de um workload de teste) porque o ponto da Parte 1 é
> praticar o fluxo do Perses, não reproduzir um dashboard de produção.

---

## Parte 1: Caminho Genérico do Cluster Observability Operator

### Conceito Rápido

O COO 1.5 GA o **Perses** como motor de dashboard **suportado**, com integração nativa no
console do OCP:

- **Zero context switching**: os dashboards aparecem em **Observe → Dashboards (Perses)**,
  dentro do próprio console — não é mais um link pra uma UI de Grafana separada.
- **Dashboard como objeto Kubernetes**: um `PersesDashboard` é um CR namespaced — versionável
  em Git, aplicável com `oc apply`, revisável em PR, igual qualquer outro recurso deste
  repositório. Diferente de um `ConfigMap` com JSON de Grafana dentro (onde só o *envelope* é
  Kubernetes, o *conteúdo* não é), no Perses o dashboard inteiro é nativo — cada painel e query
  é um campo do spec, não uma string opaca.
- **Fontes de dado em duas camadas**: `PersesDatasource` (por namespace) e
  `PersesGlobalDatasource` (cluster-wide) — o Perses procura primeiro no namespace do
  dashboard, e cai pro global se não achar. Aqui usamos um `PersesGlobalDatasource` apontando
  pro Thanos Querier padrão da própria plataforma (`openshift-monitoring`) — sem nada
  específico do ACM envolvido, já que este lab roda isolado no seu managed cluster.

---

### Pré-requisitos

- **Cluster Observability Operator 1.5+** instalado no **seu** managed cluster (via OperatorHub
  — não é algo que vem do hub/ACM).
- Permissão pra criar `UIPlugin` (cluster-scoped) e recursos no namespace `lab-perses-demo`.

---

### Passo 1: Habilitar o Perses no Console

```bash
oc apply -f 9-GrafanaToPerses/manifests/01-uiplugin-monitoring.yaml
oc apply -f 9-GrafanaToPerses/manifests/03-namespace.yaml
```

Confirme no console do seu cluster: **Observe → Dashboards (Perses)** deve aparecer no menu
lateral em alguns minutos.

---

### Passo 2: Registrar a Fonte de Dados Local

```bash
oc apply -f 9-GrafanaToPerses/manifests/02-perses-global-datasource.yaml
```

Aponta pro Thanos Querier padrão da plataforma (`thanos-querier.openshift-monitoring.svc`) —
o mesmo endpoint que qualquer painel de monitoramento nativo do OCP usa. Sem `rbac-query-proxy`
nem nada específico de ACM aqui: essa complexidade só entra em cena na Parte 2, quando o dado é
de frota, não do seu cluster sozinho.

---

### Passo 3: Gerar um Workload de Teste

```bash
oc apply -f 9-GrafanaToPerses/manifests/04-demo-deployment.yaml
```

Um `Deployment` simples (`ubi9/ubi-micro`, 2 réplicas, com `requests`/`limits` definidos) só
pra ter CPU e memória de verdade circulando no namespace `lab-perses-demo`.

---

### Passo 4: Criar o Dashboard no Perses

```bash
oc apply -f 9-GrafanaToPerses/manifests/05-persesdashboard.yaml
```

Abra **Observe → Dashboards (Perses)**, selecione o namespace `lab-perses-demo`, e abra
**Lab Perses Demo - CPU/Mem por Pod** — dois painéis, CPU e memória por pod, puxando do
Deployment do Passo 3.

> **Confira o schema antes de aplicar**: os nomes de campo do `PersesDashboard`
> (`panels`/`queries`/`layouts`) neste manifesto seguem a documentação do projeto Perses, mas
> não foram confirmados contra a versão exata do CRD instalada pelo COO. Rode
> `oc explain persesdashboard.spec` no seu cluster e ajuste se necessário.

---

### Passo 5: Editar Direto na UI (e Ver a Mudança Virar YAML)

No console, abra o dashboard e adicione/edite um painel pela interface. Confirme que a mudança
foi persistida de volta no objeto Kubernetes:

```bash
oc get persesdashboard cpu-mem-demo -n lab-perses-demo -o yaml
```

Esse é o ponto central da Parte 1: no Perses, a UI e o GitOps não são dois mundos separados —
editar na tela edita o CR, e o CR aplicado via Git edita a tela.

---

### Passo 6: Limpeza

```bash
oc delete namespace lab-perses-demo
oc delete -f 9-GrafanaToPerses/manifests/02-perses-global-datasource.yaml
oc delete -f 9-GrafanaToPerses/manifests/01-uiplugin-monitoring.yaml
```

---

## Parte 2: Caminho Oficial do ACM — Multicluster Observability Add-on (MCOA)

> **Já vem pronto no hub — a lição aqui é explorar, não configurar.** Diferente da Parte 1 (que
> cada aluno liga no próprio cluster, sem afetar mais ninguém), habilitar o MCOA com coleta de
> métricas **substitui o coletor clássico** (`observability-endpoint-operator`) por um pipeline
> novo baseado em `PrometheusAgent`/COO em **todos os managed clusters da frota** — é uma
> mudança de arquitetura pro hub inteiro, não algo por-aluno. Por isso o instrutor aplica os
> patches abaixo **uma vez, antes da aula** (mesmo espírito do boilerplate em
> [`acm-hub/`](../acm-hub/README.md) — o que já está pronto não é a lição). Os Passos 1 e 2 são
> só documentação do que já foi feito; o Passo 3 é a parte que você de fato executa.

### Conceito Rápido

O guia oficial *Red Hat Advanced Cluster Management for Kubernetes 2.17 — Observability* (seção
1.11) documenta um caminho de Perses **diferente** do da Parte 1: em vez de você criar
`UIPlugin`/`PersesDashboard` na mão, o próprio ACM entrega Perses como parte do **Multicluster
Observability Add-on (MCOA)** — um mecanismo alternativo de coleta de métricas, **Technology
Preview**, que:

- Troca o coletor de métricas do managed cluster: em vez do `observability-endpoint-operator`
  clássico, usa `PrometheusAgent` + `PrometheusOperator` do Cluster Observability Operator pra
  federar métricas direto pro hub.
- Já vem com dashboards de frota **prontos** — por exemplo, `ACM Clusters Overview` — sem você
  ter que escrever `PersesDashboard` nenhum.
- Liga em duas etapas, ambas via patch no CR `MultiClusterObservability`: primeiro o MCOA em si
  (`platform.metrics.default.enabled`), depois a UI do Perses especificamente
  (`platform.metrics.ui.enabled`).

### Passo 1 (já aplicado pelo instrutor): Habilitar o MCOA com Métricas de Plataforma

```bash
oc patch mco observability -n open-cluster-management-observability --type=merge -p \
  '{"spec":{"capabilities":{"platform":{"metrics":{"default":{"enabled":true}}}}}}'
```

Isso faz o `MultiClusterObservability` operator **parar de implantar o coletor clássico** nos
managed clusters e passar a implantar o `multicluster-observability-addon-manager`, que por sua
vez cria `PrometheusAgent` (e `ScrapeConfig`/`PrometheusRule` default) em cada cluster gerenciado.

> **Dá pra escopar, não é tudo ou nada**: o `ClusterManagementAddOn` do MCOA usa um `Placement`
> pra decidir em quais clusters o add-on entra — não precisa ser a frota inteira de uma vez. A
> **Placements UI** (ACM 2.17, Clusters → Placements → Create placement) agora mostra, **dentro
> da própria tela de criação do placement**, um preview em tempo real de quantos e quais
> clusters batem com os critérios escolhidos ("2 clusters matched", com a lista nominal) —
> antes de você confirmar nada. Dá pra testar o MCOA num placement pequeno primeiro e conferir
> visualmente o que seria afetado, em vez de assumir que "vai pra frota inteira" é a única opção.

### Passo 2 (já aplicado pelo instrutor): Habilitar a UI do Perses

```bash
oc patch mco observability -n open-cluster-management-observability --type=merge -p \
  '{"spec":{"capabilities":{"platform":{"metrics":{"default":{"enabled":true},"ui":{"enabled":true}}}}}}'
```

### Passo 3 (demonstração): Ver o Dashboard de Frota Pronto

No console do OCP: **Observe → Dashboards (Perses)** → selecione o projeto
`open-cluster-management-observability` → abra **ACM Clusters Overview**. Compare com o
dashboard que você mesmo construiu na Parte 1: aqui não teve `oc apply` de `PersesDashboard`
nenhum — o dashboard já vem do próprio ACM.

### Parte 1 vs. Parte 2, Resumo

| | Parte 1 (COO genérico) | Parte 2 (MCOA do ACM) |
|---|---|---|
| Maturidade | GA (COO 1.5) | Technology Preview |
| Você cria o `PersesDashboard`? | Sim, na mão | Não, já vem pronto (frota) |
| Muda a coleta de métricas? | Não | Sim, troca o coletor inteiro |
| Escopo do impacto | Só o dashboard/namespace do lab | Hub inteiro, todos os managed clusters |
| Bom pra | Levar seu dashboard customizado existente pro Perses | Ver a visão de frota nativa do ACM |

---

## Referências

- [Visualize your cluster: Manage observability with Red Hat build of Perses — Red Hat Developer](https://developers.redhat.com/articles/2026/07/07/manage-observability-red-hat-build-perses)
- [Red Hat build of Perses with the cluster observability operator — Red Hat Developer](https://developers.redhat.com/articles/2026/04/02/red-hat-build-perses-cluster-observability-operator)
- [How we designed customizable dashboards in OpenShift — Red Hat Developer](https://developers.redhat.com/articles/2026/07/27/how-we-designed-customizable-dashboards-openshift)
- [Cluster Observability Operator release notes](https://docs.redhat.com/en/documentation/red_hat_openshift_cluster_observability_operator/1-latest/html/red_hat_openshift_cluster_observability_operator_release_notes/cluster-observability-operator-release-notes)
- [ACM Observability — Using Grafana dashboards](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.9/html/observability/using-grafana-dashboards)
- *Red Hat Advanced Cluster Management for Kubernetes 2.17 — Observability* (guia oficial),
  seção 1.11 "Multicluster observability add-on" — cobre `Enabling the multicluster
  observability add-on` (1.11.5), `Enabling Perses dashboards with the multicluster
  observability add-on (Technology Preview)` (1.11.6) e `Viewing Perses dashboards in the
  console` (1.11.7), base da Parte 2 deste lab.
- *Red Hat Advanced Cluster Management 2.17 — "Seeing is believing"* (material de "What's New"
  da Red Hat) — apresenta Placements UI e Perses lado a lado como as duas novidades de
  visualização do release, confirma o preview em tempo real de cluster matching na tela de
  criação de `Placement`.
