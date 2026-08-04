# Exercício 8: GitOps Argo Agent Addon (ACM 2.17)

> **Ainda não validado ao vivo** — escrito com base na documentação oficial (Red Hat
> Developer + `open-cluster-management-io/ocm`), pendente de teste num hub ACM 2.17 real.
> Antes de rodar com uma turma, siga este README uma vez e ajuste o que a versão real do
> cluster exigir — principalmente nomes de pod, condições exatas e o comportamento do
> `LoadBalancer` no seu ambiente Azure/ARO.

> **Ambiente de 15 alunos, ACM só no hub**: só existe **um** hub, compartilhado — os manifestos
> deste lab usam `ApplicationSet` + `Placement` (não `Application` avulsa por aluno), então o
> **mesmo `oc apply`** funciona pra turma inteira: cada managed cluster de cada aluno (rotulado
> `whatsnewsocp-lab=true`) gera sua própria `Application` automaticamente, sem ninguém
> sobrescrever o objeto de outro colega. A instalação do addon (Passo 2) é a única parte
> **feita uma vez só, pelo instrutor** — depois disso, todo managed cluster (de qualquer aluno)
> que for importado já recebe o agent sozinho.

Neste laboratório, você vai comparar o modelo **tradicional** de GitOps multicluster do ACM
(Argo CD `ApplicationSet` + `Placement`, alcançando cada managed cluster diretamente) com o
**Argo CD Agent** (GA como addon nativo do ACM na versão 2.17) — um modelo **pull**, onde é o
managed cluster que abre conexão para o hub, não o contrário.

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
| Onde roda o `application-controller` | No hub, um por cluster gerenciado | Distribuído: um `argocd-agent-agent` leve por managed cluster |
| Resiliência a queda de rede | Sync para, hub não consegue mais falar com o spoke | Continua funcionando enquanto o spoke tiver saída pra internet |

**Componentes:**

- **Principal** (`argocd-agent-principal`): roda no hub, dentro do namespace do Argo CD
  (`argocd` por padrão). É o "servidor" que os agentes se conectam.
- **Agent** (`argocd-agent-agent`): roda em cada managed cluster, também no namespace `argocd`.
  Puxa `Application`s do principal via mTLS e reconcilia localmente — sem precisar do
  `application-controller`/`repo-server` completo do Argo CD rodando no spoke.
- **`ManagedClusterAddOn`**: é o ACM quem instala/atualiza o agent em cada managed cluster
  automaticamente, assim que ele é importado — sem passo manual por cluster.

---

## Pré-requisitos

- Hub ACM **2.17+** com o `MultiClusterHub` já instalado.
- Pelo menos um managed cluster importado (além do hub).
- OpenShift GitOps instalado no hub (o `policy-gitops-operator-install` deste repositório já
  cuida disso).
- CLI `clusteradm` instalado localmente:
  ```bash
  curl -L https://raw.githubusercontent.com/open-cluster-management-io/clusteradm/main/install.sh | bash
  ```
- Acesso de administrador ao hub e ao managed cluster de teste.

---

## Passo 1: Linha de Base — o Modelo Tradicional (push)

Aplique a `ApplicationSet` de exemplo, que usa o generator `clusterDecisionResource` (a mesma
mecânica de qualquer app hub-spoke tradicional no ACM — cluster secret + Argo CD conectando
direto no managed cluster):

```bash
oc apply -f 8-GitOpsArgoAgent/manifests/01-appset-push-model.yaml
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

No hub:

```bash
clusteradm install hub-addon --names argocd-agent --create-namespace
```

Isso cria o componente **principal** no hub e registra o addon — todo managed cluster já
importado (e qualquer um importado depois) recebe o **agent** automaticamente.

Verifique:

```bash
oc get managedclusteraddon -A | grep argocd-agent
oc -n argocd get pod -l app.kubernetes.io/name=argocd-agent-principal
oc -n argocd get gitopscluster gitops-cluster -o jsonpath='{.status.conditions}' | jq .
```

Espere `AVAILABLE=True` no `ManagedClusterAddOn` e a condição `AddonConfigured: "True"` no
`GitOpsCluster`. No managed cluster, confirme o agent:

```bash
oc --context <managed-cluster> -n argocd get pod -l app.kubernetes.io/name=argocd-agent-agent
```

---

## Passo 3: O Mesmo App, Agora via Pull

Antes de aplicar, troque `<PRINCIPAL_LB_HOST>` no manifesto pelo endereço real do load balancer
do principal (o instrutor informa esse valor — é o mesmo pra toda a turma):

```bash
oc get svc -n argocd | grep principal
```

Aplique — é o mesmo `ApplicationSet`/`Placement` do Passo 1, só muda o `destination.server`:
em vez do endpoint da API de cada managed cluster (`{{server}}`), aponta pro load balancer do
principal com o nome do cluster como query param (`{{name}}`, resolvido automaticamente por
cluster):

```bash
oc apply -f 8-GitOpsArgoAgent/manifests/02-application-pull-model.yaml
oc get application -n openshift-gitops -l app.kubernetes.io/instance=appdemo-pull
```

Compare o `spec.destination.server` da sua `Application` gerada em cada modelo (`oc get
application appdemo-push-<seu-cluster> -n openshift-gitops -o yaml` vs `oc get application
appdemo-pull-<seu-cluster> -n openshift-gitops -o yaml`) — é a única diferença estrutural
relevante entre os dois.

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

**Compartilhado** (instrutor, só depois que **todo mundo** terminar — os `ApplicationSet`s
valem pra turma inteira):

```bash
oc delete -f 8-GitOpsArgoAgent/manifests/01-appset-push-model.yaml
oc delete -f 8-GitOpsArgoAgent/manifests/02-application-pull-model.yaml
clusteradm uninstall hub-addon --names argocd-agent
```

---

## Referências

- [Multi-cluster GitOps with the Argo CD Agent Technology Preview — Red Hat](https://www.redhat.com/en/blog/multi-cluster-gitops-argo-cd-agent-openshift-gitops)
- [Using the Argo CD Agent with OpenShift GitOps — Red Hat Developer](https://developers.redhat.com/blog/2025/10/06/using-argo-cd-agent-openshift-gitops)
- [`open-cluster-management-io/ocm` — solutions/argocd-agent](https://github.com/open-cluster-management-io/ocm/tree/main/solutions/argocd-agent)
- [`argoproj-labs/argocd-agent`](https://github.com/argoproj-labs/argocd-agent)
