# Exercício 7: GitOps Argo Agent Addon (ACM 2.17, Technology Preview)

Neste laboratório, você vai pegar **a mesma aplicação** e observar ela primeiro no modelo
**tradicional** (push — Argo CD no hub conecta direto no managed cluster) e depois **migrada**
para o **Argo CD Agent** (addon do ACM 2.17, **Technology Preview**) — um modelo **pull**, onde
é o managed cluster que abre conexão para o hub, não o contrário.

> **Instância de Argo CD dedicada, não a `openshift-gitops` de produção**: este lab desliga o
> controller tradicional da instância que usa (Passo 3b). A `openshift-gitops` real deste hub
> já roda a `Application politicasdoacm-local-cluster`, que sincroniza as Policies do ACM
> (confirmado ao vivo com `oc get applications.argoproj.io -A`) — desligar o controller dela
> quebraria a automação do hub inteiro, não só a demo. Por isso todo este lab roda numa
> instância própria, isolada, no namespace `lab-argocd` (Passo 0).

---

## Conceito Rápido

No modelo tradicional (push): o Argo CD do hub tem um **Secret de cluster** com as credenciais
do managed cluster (por padrão, roteado via **cluster-proxy**, não a URL crua da API — doc
oficial, seção 1.4.4) e conecta **diretamente** para sincronizar.

O **Argo CD Agent** inverte a direção da conexão:

| | Modelo tradicional (push) | Argo CD Agent (pull) |
|---|---|---|
| Quem conecta em quem | Hub → managed cluster (via cluster-proxy) | Managed cluster → Hub |
| Requisito de rede | Hub precisa alcançar o cluster-proxy do spoke | Só o spoke precisa alcançar o hub (outbound) |
| Onde roda o `application-controller` | No hub | Distribuído: um agent leve por managed cluster |
| Como a `Application` acha o destino | `destination.server` — resolvido pelo Secret de cluster | `destination.name` — nome do managed cluster, resolvido pelo principal (`destinationBasedMapping`) |
| Resiliência a queda de rede | Sync para, hub não alcança mais o spoke | Continua funcionando enquanto o spoke tiver saída pra internet |

**Componentes** (todos no namespace `lab-argocd`, a instância dedicada deste lab):

- **Principal** (`lab-argocd-agent-principal`): roda no hub. É o "servidor" que os
  agents se conectam, com autenticação mTLS.
- **Agent** (parte do `app.kubernetes.io/part-of=argocd-agent`): roda no managed cluster,
  também no namespace `lab-argocd`. Puxa `Application`s do principal e reconcilia
  localmente.
- **`GitOpsCluster`**: o controller que automatiza a gestão de PKI, registra o Secret de
  cluster (push), e — quando `gitopsAddon` está habilitado — implanta o Argo CD Agent no
  managed cluster selecionado pelo `Placement` referenciado.

---

## Pré-requisitos

- Hub ACM **2.17+** com o `MultiClusterHub` já instalado.
- **Pelo menos um managed cluster real, separado do hub**, importado e `Joined`/`Available`
  (confirme com `oc get managedcluster`). Não use só `local-cluster`.
- Acesso de administrador ao hub.

---

## Passo 0 (já aplicado pelo instrutor): Instância Dedicada de Argo CD + `Placement`

Só o instrutor tem acesso ao hub cluster — os dois já estão aplicados:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/00-namespace.yaml
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/01-placement.yaml
oc get placementdecision -n lab-argocd -l cluster.open-cluster-management.io/placement=placement-argocd-agent-demo -o jsonpath='{.items[0].status.decisions}'
```

O `Placement` seleciona **todos** os managed clusters com o label `whatsnewsocp-lab: "true"`
(o mesmo usado no `placement-all-lab-clusters` das Policies do `acm-hub/`), sem precisar
apontar pra um cluster específico.

---

## Passo 1: Linha de Base — o Modelo Tradicional (push)

Registre o Secret de cluster (necessário mesmo pra push — doc oficial, seção 1.4.2) e aplique
a `ApplicationSet`:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/02-gitopscluster-push.yaml
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/04-push-rbac.yaml
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/03-appset-push.yaml
oc get application appdemo-<seu-cluster> -n lab-argocd
```

Espere `Synced`/`Healthy`. Confirme no managed cluster (via console ACM ou `oc --context`) que
o `Deployment appdemo` subiu no namespace `gitops-agent-demo`.

Esse é o comportamento de hoje: o Argo CD do hub fala com o managed cluster via
`destination.server`, roteado pelo cluster-proxy do ACM.

---

## Passo 2: Provar a Fragilidade do Push

Bloqueie a rota de rede que o push usa (o cluster-proxy do ACM, não a 6443 da API — o
mecanismo mudou em relação a uma versão anterior deste lab, que assumia conexão direta à API).
O jeito exato de isolar essa rota depende do seu provedor/topologia — não há um comando
genérico confiável aqui; use o troubleshooting do seu ambiente (ex.: NSG no Azure) pra
confirmar qual porta/serviço o cluster-proxy realmente usa antes de bloquear algo.

Force uma mudança (ex.: réplicas) e observe a `Application` ficar `Unknown`/`OutOfSync`.
Restaure a rede antes do próximo passo.

---

## Passo 3: Migrar pro Argo CD Agent (instrutor, uma vez só)

Diferente de um addon "liga e pronto", a doc oficial (seção 1.14) pede pra configurar o
operator e o `ArgoCD` do hub **antes** de ligar o addon via `GitOpsCluster`.

### 3a. Subscription do operator

```bash
oc patch subscription.operators openshift-gitops-operator -n openshift-gitops-operator \
  --type=merge -p '{"spec":{"config":{"env":[
    {"name":"ARGOCD_CLUSTER_CONFIG_NAMESPACES","value":"lab-argocd,local-cluster"},
    {"name":"ARGOCD_PRINCIPAL_TLS_SERVER_ALLOW_GENERATE","value":"false"},
    {"name":"ARGOCD_PRINCIPAL_REDIS_SERVER_ADDRESS","value":"lab-argocd-redis:6379"}
  ]}}}'
```

### 3b. `ArgoCD` em modo Agent

**A doc oficial manda substituir o recurso inteiro** (não é um patch parcial):

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/05-argocd-agent-mode.yaml
```

> **Isso desliga o push** (`controller.enabled: false`) — confirmado ao vivo, o
> `application-controller` clássico some (`oc get pods -n lab-argocd`). A partir daqui,
> o Passo 1 não sincroniza mais nada nesta instância (só nesta — a `openshift-gitops` de
> produção do hub nunca é tocada).

### 3c. `AppProject` wildcard e `ManagedClusterSetBinding`

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/06-appproject-wildcard.yaml
```

### 3d. Ligar o addon no `GitOpsCluster`

Mesmo objeto do Passo 1, agora com o bloco `gitopsAddon`:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/07-gitopscluster-agent.yaml
```

> **Se o status ficar preso em "addon disabled" por mais de um minuto** (confirmado ao vivo,
> acontece às vezes), reinicie o controller:
> `oc delete pod -n open-cluster-management -l app=multicluster-integrations`

### 3e. RBAC `view` pro agent (leitura)

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/08-agent-view-rbac-policy.yaml
```

### 3f. RBAC de escrita pro Argo CD local (mesmo requisito do push, seção 1.6.1)

O Argo CD **local** que o agent instala no managed cluster (`application-controller` próprio)
só tem permissão dentro do namespace onde ele mesmo vive (`lab-argocd`) — sem isso,
qualquer app cujo destino seja outro namespace (o caso normal, como este lab:
`gitops-agent-demo`) falha com `forbidden` ao aplicar. Confirmado ao vivo: sem isso, o sync
falha 5 vezes seguidas e o `Deployment` nunca é atualizado, mesmo com tudo mais certo.

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/09-agent-write-rbac-policy.yaml
```

### 3g. Verificar

```bash
oc get gitopscluster gitops-agent-clusters -n lab-argocd -o jsonpath='{.status.conditions}' | jq .
oc get managedclusteraddon gitops-addon -n <seu-cluster>
```

Espere `Ready: "True"` em todas as condições do `GitOpsCluster`, e `gitops-addon` `Available`
no `ManagedClusterAddOn`.

---

## Passo 4: Converter a Mesma App pra Pull

```bash
oc delete secret <seu-cluster>-application-manager-cluster-secret -n lab-argocd --ignore-not-found
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/10-appset-pull.yaml
oc get application appdemo-<seu-cluster> -n lab-argocd -o jsonpath='{.spec.destination}'
```

> **O `oc delete secret` acima é necessário** (confirmado ao vivo, não documentado assim na
> doc oficial): o `GitOpsCluster` do Passo 1 já tinha criado um Secret de cluster (push) pra
> esse managed cluster; ligar o agent cria um SEGUNDO Secret pro mesmo nome de cluster (agora
> via resource-proxy do agent). Os dois com o mesmo "nome" quebram a resolução do
> `destination.name` com o erro `there are 2 clusters with the same name`. Apagar o Secret
> antigo do push resolve — o `GitOpsCluster` não recria mais o de push já que o addon está
> ligado.

> **Se o primeiro sync falhar** (por exemplo, você pulou o 3f): depois de corrigir a RBAC, o
> Argo CD **não tenta de novo sozinho** uma vez esgotadas as retentativas automáticas
> (`retry.limit: 5` por padrão) — isso é comportamento padrão do Argo CD, não documentado nesse
> guia do ACM. Force uma tentativa nova commitando qualquer mudança no Git (ex.: um comentário),
> ou sincronize manualmente pela UI do Argo CD.

Repare: `destination` mudou de `server` pra `name` — é a **mesma** `Application`
(`appdemo-<seu-cluster>`), não uma segunda.

---

## Passo 5: Provar a Resiliência do Pull

Repita o mesmo bloqueio de rede do Passo 2. Diferença esperada: agora a `Application` continua
`Synced` — é o agent, rodando **no managed cluster**, que puxa a mudança; só precisa de
conectividade de **saída** pro hub, que não foi afetada pelo bloqueio (que mirava a rota do
cluster-proxy, usada só pelo push).

> **Teste alternativo, mais fácil de reproduzir e confirmado ao vivo**: em vez de bloquear rede
> (depende do seu provedor), escale o `principal` a zero — simula o hub inacessível pro agent,
> sem mexer em NSG/firewall nenhum:
> ```bash
> oc scale deployment lab-argocd-agent-principal -n lab-argocd --replicas=0
> ```
> Commite uma mudança no Git. Confirmado ao vivo: o Argo CD **local** do managed cluster
> detecta a revisão nova e tenta aplicar **mesmo sem o principal** — porque ele busca do Git
> direto, não através do hub. A aplicação de fato só depende do hub pra receber `Application`s
> **novas**/mudanças de `Placement`; o que já está configurado continua se autocurando via Git.
> Restaure o `principal` depois:
> ```bash
> oc scale deployment lab-argocd-agent-principal -n lab-argocd --replicas=1
> ```

Restaure a rede antes de seguir pra limpeza.

---

## Passo 6: Limpeza

```bash
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/10-appset-pull.yaml
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/09-agent-write-rbac-policy.yaml
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/08-agent-view-rbac-policy.yaml
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/07-gitopscluster-agent.yaml
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/06-appproject-wildcard.yaml
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/04-push-rbac.yaml
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/01-placement.yaml
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/07-GitOpsArgoAgent/manifests/00-namespace.yaml
```

O último comando remove o namespace `lab-argocd` inteiro — a instância dedicada de Argo CD
some junto, sem afetar a `openshift-gitops` de produção do hub.

---

## Referências

- *Red Hat Advanced Cluster Management for Kubernetes 2.17 — GitOps* (guia oficial), seções
  1.4 "Registering managed clusters to Red Hat OpenShift GitOps operator", 1.6 "Deploying Argo
  CD with Push and Pull model", 1.11 "Enabling Red Hat OpenShift GitOps add-on with Argo CD
  Agent (Technology Preview)" e 1.14 "Configuring subscriptions and resources for Argo CD" —
  fonte primária deste lab, seguida à risca e validada ao vivo.
- [`open-cluster-management-io/ocm` — solutions/argocd-agent](https://github.com/open-cluster-management-io/ocm/tree/main/solutions/argocd-agent)
- [`argoproj-labs/argocd-agent`](https://github.com/argoproj-labs/argocd-agent)
