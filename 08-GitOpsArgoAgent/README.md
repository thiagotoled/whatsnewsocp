# Exercício 8: GitOps Argo Agent Addon (ACM 2.17, Technology Preview)

> **Passos 1-3 validados ao vivo (push + instalação do addon); Passo 4/5 (pull) tem bloqueio
> conhecido** — reescrito com base no guia oficial *Red Hat Advanced Cluster Management for
> Kubernetes 2.17 — GitOps* (seções 1.11 e 1.14) e em correções confirmadas ao vivo num hub
> real (ver notas "confirmado ao vivo" espalhadas pelo README). Pendente: os Passos 2 e 5
> (queda de rede) ainda não foram validados, e o Passo 4 esbarra num erro de `openapi` que
> parece ser bug do Technology Preview (ver aviso antes do Passo 4).
>
> **Correção importante em relação à primeira versão deste lab**: não existe `clusteradm
> install hub-addon --names argocd-agent` no fluxo oficial do ACM. A instalação real é via um
> recurso `GitOpsCluster` com `spec.gitopsAddon.argoCDAgent.enabled: true` — bem mais
> configuração de pré-requisito do que um único comando de CLI.

> **Ambiente de 15 alunos, ACM só no hub**: só existe **um** hub, compartilhado — os manifestos
> deste lab usam `ApplicationSet` + `Placement` (não `Application` avulsa por aluno), então o
> **mesmo `oc apply`** funciona pra turma inteira: cada managed cluster de cada aluno (rotulado
> `whatsnewsocp-lab=true`) gera sua própria `Application` automaticamente, sem ninguém
> sobrescrever o objeto de outro colega. Toda a configuração de pré-requisito e a instalação do
> addon (Passo 3) são feitas **uma vez só, pelo instrutor**.

Neste laboratório, você vai pegar **a mesma aplicação** e observar ela primeiro no modelo
**tradicional** (Argo CD `ApplicationSet` + `Placement`, alcançando cada managed cluster
diretamente) e depois **convertida** pro **Argo CD Agent** (addon do ACM 2.17, **Technology
Preview**) — um modelo **pull**, onde é o managed cluster que abre conexão para o hub, não o
contrário.

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
> de **Hybrid Architecture** (Technology Preview). A ideia oficial é essa arquitetura híbrida
> servir de ponte pra migrar de Classic (push) pro Argo CD Agent (pull) gradualmente, cluster
> por cluster, em vez de trocar tudo de uma vez.

> **Uma app, dois modelos — não duas apps**: as duas primeiras versões deste lab tentavam ter
> `appdemo-push-<cluster>` e `appdemo-pull-<cluster>` como `Application`s separadas, vivas ao
> mesmo tempo, comparando lado a lado. Confirmado ao vivo: isso gera um `SharedResourceWarning`
> no Argo CD, porque as duas apontam pro mesmo `Deployment`/namespace no managed cluster — duas
> `Application`s brigando pela posse do mesmo recurso. A versão corrigida usa **um único**
> `ApplicationSet` (`appdemo`), aplicado primeiro como push, depois **convertido** pra pull (o
> Passo 4 reaplica o mesmo objeto com o campo `destination` trocado) — por isso os testes de
> rede (Passos 2 e 5) são sequenciais, não simultâneos.

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
  Passo 3a.
- `ManagedClusterSet` vinculado ao namespace `openshift-gitops` (Passo 3c).
- Acesso de administrador ao hub e ao managed cluster de teste.

> **Repo privado?** O `repoURL` deste lab (`01-appset-push-model.yaml`/
> `02-application-pull-model.yaml`) aponta pro repositório público do curso — não precisa de
> credencial. Só crie um `Secret` do tipo `repository` (label
> `argocd.argoproj.io/secret-type: repository`) em `openshift-gitops` se você trocar o
> `repoURL` por um fork privado seu.

---

## Passo 1: Linha de Base — o Modelo Tradicional (push)

Primeiro, dê ao ApplicationSet controller permissão pra ler `PlacementDecisions` — sem isso a
`ApplicationSet` não gera **nenhuma** `Application`, sem erro óbvio no `oc get applicationset`
(confirmado ao vivo, foi a causa real de o Passo 1 falhar antes de qualquer coisa do Agent
entrar em cena):

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/00-appset-placementdecisions-rbac.yaml
```

Agora aplique a `ApplicationSet` de exemplo, que usa o generator `clusterDecisionResource` (a
mesma mecânica de qualquer app hub-spoke tradicional no ACM — cluster secret + Argo CD
conectando direto no managed cluster):

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/01-appset-push-model.yaml
oc get applicationset appdemo -n openshift-gitops
oc get application -n openshift-gitops -l app.kubernetes.io/instance=appdemo
```

O segundo comando lista uma `Application` (`appdemo-<nome-do-cluster>`) por managed cluster
rotulado `whatsnewsocp-lab=true` na turma inteira — ache a sua pelo nome do seu cluster.
Confirme no managed cluster que o Deployment subiu:

```bash
oc get deployment appdemo -n gitops-agent-demo --context <managed-cluster>
```

Esse é o comportamento de hoje: o Argo CD do hub está falando **diretamente** com a API do
managed cluster (`spec.destination.server`).

---

## Passo 2: Provar a Fragilidade do Push

Antes de instalar o Agent, prove o problema que ele resolve. É individual — cada aluno bloqueia
só a rede do **próprio** managed cluster, sem afetar os colegas.

> **Não é "bloquear tudo"** — é bloquear especificamente a porta **6443** (API server), que é
> por onde o push conecta. O agent (Passo 5) conecta outbound pro principal via **Route do hub
> (443/HTTPS)**, uma porta completamente diferente — então bloquear só a 6443 já isola o
> mecanismo certo, sem derrubar a rede inteira nem arriscar cortar seu próprio `oc login`
> (que também usa 6443, mas de qualquer origem, não só do hub).
>
> **Não edite a regra `apiserver_in` do NSG** — no ARO, ela é gerenciada pela plataforma e
> pode ser revertida pela reconciliação. Em vez disso, **adicione uma regra nova com
> prioridade menor** (avaliada antes, já que Azure NSG usa "número menor = maior
> prioridade"), escopada só pro IP de saída do hub.
>
> **Sem comando pronto de propósito** — o NSG/resource group varia por ambiente/aluno e isso
> ainda não foi validado de ponta a ponta; monte a regra (`az network nsg rule create`, Deny,
> Inbound, porta 6443, source = IP de saída do hub) direto no seu ambiente em vez de copiar um
> comando genérico daqui.

Force uma mudança (ex.: mude o número de réplicas no manifesto e reaplique só a fonte Git) e
observe sua `Application` (`appdemo-<seu-cluster>`): ela fica `Unknown`/`OutOfSync` sem
conseguir reconciliar — o Argo CD do hub não alcança mais o seu managed cluster pra aplicar
nada.

**Restaure a rede** (remova a regra que você criou) antes de seguir pro próximo passo — o
Passo 4 precisa que o push volte a sincronizar normalmente antes de converter.

---

## Passo 3: Instalar o Argo CD Agent Addon (instrutor, uma vez só)

Diferente de um addon "liga e pronto", o modo Agent do OpenShift GitOps exige configurar o
operator e o `ArgoCD` do hub antes de criar o `GitOpsCluster`. São 7 sub-passos, todos no hub.

### 3a. Configurar a Subscription do operator

```bash
oc patch subscription.operators openshift-gitops-operator -n openshift-gitops-operator \
  --type=merge -p '{"spec":{"config":{"env":[
    {"name":"ARGOCD_CLUSTER_CONFIG_NAMESPACES","value":"openshift-gitops,local-cluster"},
    {"name":"ARGOCD_PRINCIPAL_TLS_SERVER_ALLOW_GENERATE","value":"false"},
    {"name":"ARGOCD_PRINCIPAL_REDIS_SERVER_ADDRESS","value":"openshift-gitops-redis:6379"}
  ]}}}'
```

### 3b. Adicionar a configuração de modo Agent no `ArgoCD` existente

**Importante — use `oc patch`, não `oc apply -f`.** Um `oc apply -f` de um `ArgoCD` inteiro
reescreve o `spec` todo e derruba o `controller.enabled` (que precisa continuar ligado — é
ele que faz o Passo 1/push funcionar). O `03-argocd-agent-mode.yaml` deste lab é só a
*referência* do fragmento; aplique via patch:

```bash
oc patch argocd openshift-gitops -n openshift-gitops --type=merge -p '{
  "spec": {
    "sourceNamespaces": ["*"],
    "argoCDAgent": {
      "principal": {
        "enabled": true,
        "destinationBasedMapping": true,
        "auth": "mtls:CN=system:open-cluster-management:cluster:([^:]+):addon:gitops-addon:agent:gitops-addon-agent",
        "namespace": {"allowedNamespaces": ["*"]},
        "server": {"route": {"enabled": true}}
      }
    }
  }
}'
```

Isso liga o principal com `destinationBasedMapping: true` (é o que faz
`destination.name: '{{name}}'` funcionar no Passo 4) **sem tocar** no controller tradicional
do push — confirmado ao vivo: com `controller.enabled: false` (como uma primeira versão deste
lab tinha, seguindo um exemplo da doc oficial escrito pra modo Agent puro, não híbrido), o
Passo 1 quebra.

### 3c. `AppProject` wildcard e `ManagedClusterSetBinding`

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/04-appproject-wildcard.yaml
oc apply -f 08-GitOpsArgoAgent/manifests/05-managedclustersetbinding.yaml
```

> Confira se `clusterSet: default` bate com o seu hub (`oc get managedclusterset`) — ajuste o
> manifesto se o nome for outro.

### 3d. Criar o `GitOpsCluster` (isso é o que de fato liga o addon)

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/06-gitopscluster-agent.yaml
```

### 3e. RBAC pro agent nos managed clusters

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/07-agent-view-clusterrolebinding.yaml
```

> **Sem isso o processo do agent crasha no startup** (`CrashLoopBackOff`), confirmado ao vivo:
> `[FATAL]: Could not start agent: applications.argoproj.io is forbidden ... cannot list
> resource "applications" ... at the cluster scope`. A `ClusterRole` `view` sozinha **não**
> resolve — `applications`/`appprojects`/`applicationsets` não têm o label
> `aggregate-to-view`, então o manifesto concede as duas coisas: `view` (recursos nativos) +
> uma `ClusterRole` própria pra `argoproj.io`.

### 3f. RBAC pro Push Model Funcionar

Sem isso, o `application-controller` recebe `forbidden` ao tentar criar recursos nos managed
clusters — a `Application` do Passo 1 fica presa em erro de sync mesmo com o resto certo
(confirmado ao vivo; também documentado na doc oficial, seção 1.6, aviso "Important"):

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/08-push-model-rbac.yaml
```

### 3g. RBAC extra do principal (gap confirmado ao vivo)

A `ClusterRole` que o operator gera automaticamente pro principal
(`openshift-gitops-openshift-gitops-agent-principal`) dá acesso a `applications`/
`appprojects`/`applicationsets`, mas **não** ao subresource `/status` deles — RBAC no
Kubernetes trata subresource separado do recurso base. Sem isso, o principal falha ao gravar o
status de volta na `Application` (`the server rejected our request due to an error in our
request`), mesmo com tudo mais certo. Parece gap real do Technology Preview, não erro deste
lab:

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/09-principal-status-rbac.yaml
```

### 3h. Verificar

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

> **Bloqueio conhecido, ainda sem correção (confirmado ao vivo, GitOps 1.21.1)**: mesmo com
> tudo acima aplicado e o agent `Running` (não mais `CrashLoopBackOff`) e autenticando via mTLS
> com sucesso, a `Application` convertida pra pull (Passo 4) pode ficar presa em
> `ComparisonError`: `failed to load open api schema while syncing cluster cache: error
> getting openapi resources: the server rejected our request for an unknown reason`. O agent
> consegue buscar `/openapi/v2` direto (`curl` retorna `200`), então não é RBAC — parece uma
> limitação do resource-proxy do `argocd-agent` v0.9.0 (Technology Preview) ao retransmitir
> essa chamada específica (não é um recurso tipado, é uma URL não-resource). Não achamos
> workaround ainda. Se isso acontecer com você, é esperado — não é erro de configuração deste
> lab; documente como "limitação conhecida do TP" na apresentação em vez de tentar contornar
> ao vivo.

## Passo 4: Converter a Mesma App pra Pull

Reaplique o **mesmo** `ApplicationSet` (`appdemo`) — só o campo `destination` muda: em vez do
endpoint da API de cada managed cluster (`destination.server: '{{server}}'`), usa
`destination.name: '{{name}}'` — o principal resolve pelo nome do managed cluster
(`destinationBasedMapping`, configurado no Passo 3b), sem load balancer nem query param
nenhum:

```bash
oc apply -f 08-GitOpsArgoAgent/manifests/02-application-pull-model.yaml
oc get application appdemo-<seu-cluster> -n openshift-gitops -o yaml
```

Repare: é a **mesma** `Application` (`appdemo-<seu-cluster>`, mesmo nome de antes) — só o
`spec.destination` mudou de `server` pra `name`. Não foi criada uma segunda `Application`.

> **Bônus — ver isso visualmente**: o OpenShift GitOps 1.21 traz um **Console Plugin/UI**
> (Technology Preview) com uma view nova de topologia de `Application`/`ApplicationSet`. Se
> estiver habilitado no seu hub, vale abrir e ver a mesma `Application` antes/depois da
> conversão, em vez de só ler YAML pelo `oc get`.

---

## Passo 5: Provar a Resiliência do Pull

Recrie **exatamente** a mesma regra de bloqueio do Passo 2 (Deny, Inbound, porta 6443, mesmo
IP de saída do hub) e force a mesma mudança (réplicas, por exemplo):

- No Passo 2 (push), a `Application` ficava `Unknown`/`OutOfSync`.
- Agora (pull), ela **continua sincronizando normalmente** — é o **agent no seu managed
  cluster** que puxa a mudança do principal, então só precisa de conectividade **de saída**,
  que nunca foi interrompida (a 6443 bloqueada nem entra em jogo — o agent fala com o hub via
  Route/443, não pela API do managed cluster).

Esse é o ponto central do lab: a mesma aplicação, a mesma queda de rede, comportamento
diferente — só porque o campo `destination` mudou no Passo 4.

Restaure a rede (remova a regra) antes de seguir pra limpeza.

---

## Passo 6: Limpeza

**Individual** (cada aluno, no próprio managed cluster):

```bash
oc --context <managed-cluster> delete namespace gitops-agent-demo
```

**Compartilhado** (instrutor, só depois que **todo mundo** terminar — o `ApplicationSet` e
o addon valem pra turma inteira):

```bash
oc delete -f 08-GitOpsArgoAgent/manifests/01-appset-push-model.yaml
oc delete -f 08-GitOpsArgoAgent/manifests/00-appset-placementdecisions-rbac.yaml
oc delete -f 08-GitOpsArgoAgent/manifests/07-agent-view-clusterrolebinding.yaml
oc delete -f 08-GitOpsArgoAgent/manifests/08-push-model-rbac.yaml
oc delete -f 08-GitOpsArgoAgent/manifests/09-principal-status-rbac.yaml
oc delete gitopscluster gitops-agent-clusters -n openshift-gitops
```

---

## Referências

- *Red Hat Advanced Cluster Management for Kubernetes 2.17 — GitOps* (guia oficial), seções
  1.6 "Deploying Argo CD with Push and Pull model" (aviso RBAC do `application-controller`),
  1.11 "Enabling Red Hat OpenShift GitOps add-on with Argo CD Agent (Technology Preview)" e
  1.14 "Configuring subscriptions and resources for Argo CD" — fonte primária deste lab,
  substitui os blog posts usados na primeira versão.
- [`open-cluster-management-io/ocm` — solutions/argocd-agent](https://github.com/open-cluster-management-io/ocm/tree/main/solutions/argocd-agent)
- [`argoproj-labs/argocd-agent`](https://github.com/argoproj-labs/argocd-agent)
- *OpenShift GitOps 1.21 Release Highlights* (material de "What's New" da Red Hat) — confirma
  as versões dos componentes (Argo CD 3.4, Argo CD Agent 0.9, Argo Rollouts 1.9) e nomeia
  oficialmente a **Hybrid Architecture** (Technology Preview) e o **Console Plugin/UI**
  (Technology Preview) usados neste lab.
