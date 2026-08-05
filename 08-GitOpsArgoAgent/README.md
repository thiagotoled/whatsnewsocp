# Exercício 8: GitOps Argo Agent Addon (ACM 2.17, Technology Preview)

> **Ainda não validado ao vivo** — reescrito com base no guia oficial *Red Hat Advanced Cluster
> Management for Kubernetes 2.17 — GitOps* (seções 1.11 e 1.14), que substituiu por completo a
> minha primeira versão baseada em blog posts. Pendente de teste num hub ACM 2.17 real —
> principalmente os nomes exatos de pod/namespace e o comportamento de
> `destinationBasedMapping` no seu ambiente.
>
> **Correção importante em relação à versão anterior deste lab**: não existe `clusteradm
> install hub-addon --names argocd-agent` no fluxo oficial do ACM. A instalação real é via um
> recurso `GitOpsCluster` com `spec.gitopsAddon.argoCDAgent.enabled: true` — bem mais
> configuração de pré-requisito do que um único comando de CLI.

> **Ambiente de 15 alunos, ACM só no hub**: só existe **um** hub, compartilhado — os manifestos
> deste lab usam `ApplicationSet` + `Placement` (não `Application` avulsa por aluno), então o
> **mesmo `oc apply`** funciona pra turma inteira: cada managed cluster de cada aluno (rotulado
> `whatsnewsocp-lab=true`) gera sua própria `Application` automaticamente, sem ninguém
> sobrescrever o objeto de outro colega. Toda a configuração de pré-requisito e a instalação do
> addon (Passo 2) são feitas **uma vez só, pelo instrutor**.

Neste laboratório, você vai comparar o modelo **tradicional** de GitOps multicluster do ACM
(Argo CD `ApplicationSet` + `Placement`, alcançando cada managed cluster diretamente) com o
**Argo CD Agent** (addon do ACM 2.17, **Technology Preview**) — um modelo **pull**, onde é o
managed cluster que abre conexão para o hub, não o contrário.

> **Versões (OpenShift GitOps 1.21)**: Argo CD 3.4, Argo CD Agent **0.9**, Argo Rollouts 1.9 —
> confira `oc get csv -n openshift-gitops-operator | grep gitops` no seu hub pra bater com a
> versão instalada antes de rodar o lab.

---

## Conceito Rápido

No modelo tradicional (o que este repositório já usa, e o que você provavelmente já construiu
como "AppDemo" hub-spoke): o Argo CD do hub tem um **cluster secret** com as credenciais de
cada managed cluster e conecta **diretamente** na API deles pra sincronizar. Isso exige que o
**hub alcance a rede de cada spoke** — em ambientes com firewall restritivo, VPN instável ou
clusters atrás de NAT, isso é um problema real.

O **Argo CD Agent** inverte a direção da conexão:

| | Modelo tradicional (push) | Argo CD Agent (pull) |
|---|---|---|
| Quem conecta em quem | Hub → managed cluster | Managed cluster → Hub |
| Requisito de rede | Hub precisa alcançar todo spoke | Só o spoke precisa alcançar o hub (outbound) |
| Onde roda o `application-controller` | No hub, um por cluster gerenciado | Distribuído: um agent leve por managed cluster |
| Como a `Application` acha o destino | `destination.server` — endpoint da API do managed cluster | `destination.name` — nome do managed cluster, resolvido pelo principal (`destinationBasedMapping`) |
| Resiliência a queda de rede | Sync para, hub não consegue mais falar com o spoke | Continua funcionando enquanto o spoke tiver saída pra internet |

> **Isso tem nome**: o OpenShift GitOps 1.21 chama exatamente essa combinação — push e pull
> coexistindo na **mesma instância** de Argo CD do hub, sem precisar de dois Argo CD separados —
> de **Hybrid Architecture** (Technology Preview). É literalmente o que os Passos 1 e 3 deste
> lab fazem: a mesma `ApplicationSet`/`Placement`, o mesmo `openshift-gitops` no hub, só troca
> o campo `destination` de cada `Application`. A ideia oficial é essa arquitetura híbrida servir
> de ponte pra migrar de Classic (push) pro Argo CD Agent (pull) gradualmente, cluster por
> cluster, em vez de trocar tudo de uma vez.

**Componentes** (todos no namespace `openshift-gitops`, não `argocd`):

- **Principal** (`openshift-gitops-agent-principal`): roda no hub. É o "servidor" que os
  agents se conectam, com autenticação mTLS.
- **Agent** (parte do `app.kubernetes.io/part-of=argocd-agent`): roda em cada managed
  cluster, também no namespace `openshift-gitops`. Puxa `Application`s do principal e
  reconcilia localmente.
- **`GitOpsCluster`**: o controller que automatiza toda a gestão de PKI, cria os
  `ManagedClusterAddOn`/`AddOnDeploymentConfig` por managed cluster, e implanta o Argo CD
  Agent em cada cluster selecionado pelo `Placement` referenciado.

---

## Pré-requisitos

- Hub ACM **2.17+** com o `MultiClusterHub` já instalado.
- Pelo menos um managed cluster importado (além do hub), rotulado `whatsnewsocp-lab: "true"`.
- OpenShift GitOps instalado no hub (o `policy-gitops-operator-install` deste repositório já
  cuida disso), com a `Subscription` do operator configurada com as variáveis de ambiente do
  Passo 2a.
- `ManagedClusterSet` vinculado ao namespace `openshift-gitops` (Passo 2c).
- Acesso de administrador ao hub e ao managed cluster de teste.

---

## Passo 1: Linha de Base — o Modelo Tradicional (push)

Aplique a `ApplicationSet` de exemplo, que usa o generator `clusterDecisionResource` (a mesma
mecânica de qualquer app hub-spoke tradicional no ACM — cluster secret + Argo CD conectando
direto no managed cluster):

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/01-appset-push-model.yaml
oc get applicationset appdemo-push -n openshift-gitops
oc get application -n openshift-gitops -l app.kubernetes.io/instance=appdemo-push
```

O segundo comando lista uma `Application` (`appdemo-push-<nome-do-cluster>`) por managed
cluster rotulado `whatsnewsocp-lab=true` na turma inteira — ache a sua pelo nome do seu
cluster. Confirme no managed cluster que o Deployment subiu:

```bash
oc get deployment appdemo -n gitops-agent-demo --context <managed-cluster>
```

Esse é o comportamento de hoje: o Argo CD do hub está falando **diretamente** com a API do
managed cluster.

---

## Passo 2: Instalar o Argo CD Agent Addon (instrutor, uma vez só)

Diferente de um addon "liga e pronto", o modo Agent do OpenShift GitOps exige configurar o
operator e o `ArgoCD` do hub antes de criar o `GitOpsCluster`. São 6 sub-passos, todos no hub.

### 2a. Configurar a Subscription do operator

```bash
oc patch subscription.operators openshift-gitops-operator -n openshift-gitops-operator \
  --type=merge -p '{"spec":{"config":{"env":[
    {"name":"ARGOCD_CLUSTER_CONFIG_NAMESPACES","value":"openshift-gitops,local-cluster"},
    {"name":"ARGOCD_PRINCIPAL_TLS_SERVER_ALLOW_GENERATE","value":"false"},
    {"name":"ARGOCD_PRINCIPAL_REDIS_SERVER_ADDRESS","value":"openshift-gitops-redis:6379"}
  ]}}}'
```

### 2b. Substituir o `ArgoCD` pela configuração de modo Agent

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/03-argocd-agent-mode.yaml
```

Isso desliga o controller tradicional (`controller.enabled: false`) e liga o principal com
`destinationBasedMapping: true` — é isso que faz `destination.name: '{{name}}'` funcionar no
Passo 3.

### 2c. `AppProject` wildcard e `ManagedClusterSetBinding`

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/04-appproject-wildcard.yaml
oc apply -f 08-GitOpsArgoAgent/manifests/05-managedclustersetbinding.yaml
```

> Confira se `clusterSet: default` bate com o seu hub (`oc get managedclusterset`) — ajuste o
> manifesto se o nome for outro.

### 2d. Criar o `GitOpsCluster` (isso é o que de fato liga o addon)

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/06-gitopscluster-agent.yaml
```

### 2e. Conceder a role `view` pro agent nos managed clusters

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/07-agent-view-clusterrolebinding.yaml
```

### 2f. Verificar

```bash
oc get gitopscluster gitops-agent-clusters -n openshift-gitops -o jsonpath='{.status.conditions}' | jq .
oc get pods -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-agent-principal
```

Espere `Ready: "True"` (e as condições `PlacementResolved`, `ClustersRegistered`,
`ArgoCDAgentPrereqsReady`, `CertificatesReady`, `ManifestWorksApplied`) no `GitOpsCluster`. No
managed cluster, confirme o agent:

```bash
oc --context <managed-cluster> get pods -n openshift-gitops -l app.kubernetes.io/part-of=argocd-agent
```

---

## Passo 3: O Mesmo App, Agora via Pull

Aplique — é o mesmo `ApplicationSet`/`Placement` do Passo 1, só muda o campo `destination`: em
vez do endpoint da API de cada managed cluster (`destination.server: '{{server}}'`), usa
`destination.name: '{{name}}'` — o principal resolve pelo nome do managed cluster
(`destinationBasedMapping`, configurado no Passo 2b), sem load balancer nem query param
nenhum:

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/02-application-pull-model.yaml
oc get application -n openshift-gitops -l app.kubernetes.io/instance=appdemo-pull
```

Compare o `spec.destination` da sua `Application` gerada em cada modelo (`oc get application
appdemo-push-<seu-cluster> -n openshift-gitops -o yaml` vs `oc get application
appdemo-pull-<seu-cluster> -n openshift-gitops -o yaml`) — é a única diferença estrutural
relevante entre os dois.

> **Bônus — ver isso visualmente**: o OpenShift GitOps 1.21 traz um **Console Plugin/UI**
> (Technology Preview) com uma view nova de topologia de `Application`/`ApplicationSet`. Se
> estiver habilitado no seu hub, vale abrir e comparar visualmente as duas `Application`s
> (`appdemo-push-<seu-cluster>` e `appdemo-pull-<seu-cluster>`) lado a lado, em vez de só ler
> YAML pelo `oc get`.

---

## Passo 4: A Prova de Verdade — Derrubar a Rede Hub → Seu Managed Cluster

Esse é o ponto central do lab, e é individual — cada aluno bloqueia só a rede do **próprio**
managed cluster, sem afetar os colegas. No Azure, bloqueie tráfego **inbound** no NSG do seu
managed cluster vindo do hub (mantendo a saída liberada):

```bash
# Ajuste ao seu ambiente -- o objetivo é: hub NÃO consegue mais iniciar conexão pro SEU
# managed cluster, mas ele ainda consegue falar com o hub (outbound liberado).
```

Force uma mudança nos dois apps (ex.: mude o número de réplicas no manifesto e reaplique só a
fonte Git) e observe **as suas duas `Application`s** (`appdemo-push-<seu-cluster>` e
`appdemo-pull-<seu-cluster>`):

- **`appdemo-push-<seu-cluster>`**: fica `Unknown`/`OutOfSync` sem conseguir reconciliar — o
  Argo CD do hub não alcança mais o seu managed cluster pra aplicar nada.
- **`appdemo-pull-<seu-cluster>`**: continua sincronizando normalmente — é o **agent no seu
  managed cluster** que puxa a mudança do principal, então só precisa de conectividade **de
  saída**, que nunca foi interrompida.

---

## Passo 5: Limpeza

**Individual** (cada aluno, no próprio managed cluster):

```bash
oc --context <managed-cluster> delete namespace gitops-agent-demo
```

**Compartilhado** (instrutor, só depois que **todo mundo** terminar — os `ApplicationSet`s e
o addon valem pra turma inteira):

```bash
oc delete -f 08-GitOpsArgoAgent/manifests/01-appset-push-model.yaml
oc delete -f 08-GitOpsArgoAgent/manifests/02-application-pull-model.yaml
oc delete -f 08-GitOpsArgoAgent/manifests/07-agent-view-clusterrolebinding.yaml
oc delete gitopscluster gitops-agent-clusters -n openshift-gitops
```

---

## Referências

- *Red Hat Advanced Cluster Management for Kubernetes 2.17 — GitOps* (guia oficial), seções
  1.11 "Enabling Red Hat OpenShift GitOps add-on with Argo CD Agent (Technology Preview)" e
  1.14 "Configuring subscriptions and resources for Argo CD" — fonte primária deste lab,
  substitui os blog posts usados na primeira versão.
- [`open-cluster-management-io/ocm` — solutions/argocd-agent](https://github.com/open-cluster-management-io/ocm/tree/main/solutions/argocd-agent)
- [`argoproj-labs/argocd-agent`](https://github.com/argoproj-labs/argocd-agent)
- *OpenShift GitOps 1.21 Release Highlights* (material de "What's New" da Red Hat) — confirma
  as versões dos componentes (Argo CD 3.4, Argo CD Agent 0.9, Argo Rollouts 1.9) e nomeia
  oficialmente a **Hybrid Architecture** (Technology Preview) e o **Console Plugin/UI**
  (Technology Preview) usados neste lab.
