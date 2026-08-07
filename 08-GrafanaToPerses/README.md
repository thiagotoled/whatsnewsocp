# Exercício 9: Dashboards com o Red Hat Build of Perses — Dois Caminhos

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

- **Cluster Observability Operator 1.5+** instalado no **seu** managed cluster. **Criado por
  política**: se seu cluster foi importado no hub com ACM, o `policy-lab08` já instala o COO e
  cria o namespace `lab-perses-demo` — confira antes de instalar via OperatorHub na mão.
- Permissão pra criar `UIPlugin` (cluster-scoped) e recursos no namespace `lab-perses-demo`.

---

### Passo 1: Habilitar o Perses no Console

Sem ACM, crie também o namespace (`03-namespace.yaml`); o `UIPlugin` é sempre manual — é a
lição deste lab:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/08-GrafanaToPerses/manifests/01-uiplugin-monitoring.yaml
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/08-GrafanaToPerses/manifests/03-namespace.yaml
```

Confirme no console do seu cluster: **Observe → Dashboards (Perses)** deve aparecer no menu
lateral em alguns minutos.

---

### Passo 2: Registrar a Fonte de Dados Local

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/08-GrafanaToPerses/manifests/02-perses-global-datasource.yaml
```

Aponta pro Thanos Querier padrão da plataforma (`thanos-querier.openshift-monitoring.svc`) —
o mesmo endpoint que qualquer painel de monitoramento nativo do OCP usa. Sem `rbac-query-proxy`
nem nada específico de ACM aqui: essa complexidade só entra em cena na Parte 2, quando o dado é
de frota, não do seu cluster sozinho.

---

### Passo 3: Gerar um Workload de Teste

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/08-GrafanaToPerses/manifests/04-demo-deployment.yaml
```

Um `Deployment` simples (`ubi9/ubi-micro`, 2 réplicas, com `requests`/`limits` definidos) só
pra ter CPU e memória de verdade circulando no namespace `lab-perses-demo`.

---

### Passo 4: Criar o Dashboard no Perses

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/08-GrafanaToPerses/manifests/05-persesdashboard.yaml
```

Abra **Observe → Dashboards (Perses)**, selecione o namespace `lab-perses-demo`, e abra
**Lab Perses Demo - CPU/Mem por Pod** — dois painéis, CPU e memória por pod, puxando do
Deployment do Passo 3.

---

### Passo 5: Limpeza

```bash
oc delete namespace lab-perses-demo
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/08-GrafanaToPerses/manifests/02-perses-global-datasource.yaml
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/08-GrafanaToPerses/manifests/01-uiplugin-monitoring.yaml
```

---

## Parte 2: Caminho Oficial do ACM — Multicluster Observability Add-on (MCOA)

### Conceito Rápido

O guia oficial *Red Hat Advanced Cluster Management for Kubernetes 2.17 — Observability* (seção
1.11) documenta um caminho de Perses **diferente** do da Parte 1: em vez de você criar
`UIPlugin`/`PersesDashboard` na mão, o próprio ACM entrega Perses como parte do **Multicluster
Observability Add-on (MCOA)** — um mecanismo alternativo de coleta de métricas, **Technology
Preview**.

### Passo 1 (já aplicado pelo instrutor): Habilitar o MCOA com Métricas de Plataforma

```bash
oc patch mco observability -n open-cluster-management-observability --type=merge -p \
  '{"spec":{"capabilities":{"platform":{"metrics":{"default":{"enabled":true}}}}}}'
```

### Passo 2 (já aplicado pelo instrutor): Habilitar a UI do Perses

```bash
oc patch mco observability -n open-cluster-management-observability --type=merge -p \
  '{"spec":{"capabilities":{"platform":{"metrics":{"default":{"enabled":true},"ui":{"enabled":true}}}}}}'
```

Confirmado ao vivo: esse patch já instala sozinho o Cluster Observability Operator **no hub**
(diferente da Parte 1, que depende do `policy-lab08` no managed cluster) — não precisa de
nenhum passo extra de operator aqui.

### Passo 3 (demonstração): Ver o Dashboard de Frota Pronto

No console do OCP: **Observe → Dashboards (Perses)** → selecione o projeto
`open-cluster-management-observability` → abra **ACM Clusters Overview**. Compare com o
dashboard que você mesmo construiu na Parte 1: aqui não teve `oc apply` de `PersesDashboard`
nenhum — o dashboard já vem do próprio ACM.

---

## Referências

- [Visualize your cluster: Manage observability with Red Hat build of Perses — Red Hat Developer](https://developers.redhat.com/articles/2026/07/07/manage-observability-red-hat-build-perses)
- [Red Hat build of Perses with the cluster observability operator — Red Hat Developer](https://developers.redhat.com/articles/2026/04/02/red-hat-build-perses-cluster-observability-operator)
- [How we designed customizable dashboards in OpenShift — Red Hat Developer](https://developers.redhat.com/articles/2026/07/27/how-we-designed-customizable-dashboards-openshift)
- [Cluster Observability Operator release notes](https://docs.redhat.com/en/documentation/red_hat_openshift_cluster_observability_operator/1-latest/html/red_hat_openshift_cluster_observability_operator_release_notes/cluster-observability-operator-release-notes)
- [ACM Observability — Using Grafana dashboards](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.9/html/observability/using-grafana-dashboards)
