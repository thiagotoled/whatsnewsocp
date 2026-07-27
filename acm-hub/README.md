# Estratégia de ACM (Advanced Cluster Management) para os Labs

Este diretório prepara, **antes de existir o hub**, tudo que vai ser aplicado via RHACM
Policy assim que o hub estiver pronto. O restante do repositório (`InplacePodverticalscaling/`,
`UpgradeRecommendPrecheck/`, etc.) continua igual — cada lab é aplicado manualmente com
`oc apply -f` pelo aluno/instrutor, exatamente como hoje.

> **Status:** o hub ainda não existe (vai ser um cluster novo, criado do zero). Nada aqui foi
> testado contra um hub real — é esqueleto baseado no schema conhecido do RHACM. Validar/ajustar
> assim que o hub subir.

---

## Por que usar ACM Policy aqui?

Dois motivos, não um só:

1. **Reduzir trabalho repetitivo**: parte de cada lab é só "prep" (namespace, deployment,
   operador instalado) — não é a lição em si. Isso pode ficar pronto no cluster antes da
   sessão começar.
2. **Resolver o problema de timing do Lab 9**: o alerta `PodDisruptionBudgetAtLimit` só vira
   `firing` depois de **60 minutos** (`for: 60m` na regra do Prometheus). Se o PDB for criado
   na hora do lab, o `oc adm upgrade recommend` não vai mostrar nada. Semeando o PDB via
   Policy com bastante antecedência, ele já está `firing` quando a turma chega nesse passo.

---

## Regra de ouro: boilerplate vs. lição

**Boilerplate** (pode virar Policy, pré-criado) = tudo que existe só para o aluno ter onde
aplicar a lição, e que não muda o entendimento do conceito se já estiver lá.

**Lição** (fica manual, `oc apply -f` pelo aluno) = o passo que É o conceito sendo ensinado.
Se isso for pré-criado, o aluno perde o "antes/depois" e a lição não acontece.

| Lab | Boilerplate (→ Policy) | Lição (fica manual) |
|---|---|---|
| 1. InplacePodverticalscaling | namespace + deployment | `oc patch --subresource=resize` |
| 2. ExternalSecretsOperator | namespace + instalação do operador | SecretStore/ExternalSecret (pull e push) |
| 3. UserNamespaces | namespace | os dois Deployments (comparação é a lição) |
| 4. ManagedBootImages | *(nada)* | o único manifesto do lab é a lição inteira |
| 5. VulnerabilityManagementReporting | namespace + deployment vulnerável | gerar/ler o relatório |
| 6. PolicyScopeLabels | namespaces prod/dev + deployment latest-tag | a Policy com escopo por label |
| 7. PolicyDebugPodAttach | namespace + deployment | `oc debug`/`oc attach` + reação do RHACS |
| 9. UpgradeRecommendPrecheck | namespace + deployment **+ PDB restritivo (ver aviso abaixo)** | corrigir o PDB e ver o precheck refletir |

Além do boilerplate por lab, existem 3 policies de **bootstrap do próprio hub** (não são de nenhum
lab específico), trazidas do repo real `ACM_OCP/Politicas` e adaptadas:

| Policy | O que faz | Onde roda |
|---|---|---|
| `policy-gitops-operator-install` | Instala o OpenShift GitOps operator | `local-cluster` (o hub) |
| `policy-webterminal-install` | Instala o Web Terminal operator | `local-cluster` (o hub) |
| `policy-oauth-configuration` | Configura OAuth (HTPasswd + Entra ID/AAD via OIDC) | **`all`** — todo managed cluster OpenShift (hub + Azure + VMware), mesmo login em qualquer console |

---

## ⚠️ Cuidado com o PDB do Lab 9 (drift/enforce)

A policy `policy-lab09-upgrade-recommend-precheck-pdb-seed` roda em `remediationAction: enforce`
de propósito, para o PDB existir com bastante antecedência (fluxo do "por que" acima). Só que,
em `enforce`, o ACM **reverte qualquer mudança manual** assim que detecta drift.

Isso quebra o Passo 5 do lab (o aluno aplica `04-poddisruptionbudget-fixed.yaml` para corrigir
o PDB) — a policy vai desfazer a correção do aluno.

**Antes de liberar a turma para o Passo 5**, desabilite só essa policy:

```bash
oc patch policy policy-lab09-upgrade-recommend-precheck-pdb-seed \
  -n whatsnewsocp-policies --type merge -p '{"spec":{"disabled":true}}'
```

(Ou delete a policy — o PDB já criado continua no cluster, só para de ser reconciliado.)

---

## ⚠️ Cuidado com a `policy-oauth-configuration` (Redirect URI do Entra ID)

Essa policy reaproveita o **mesmo app registration** do Entra ID usado em `ACM_OCP/Politicas`
(hash do htpasswd, client secret e client ID/tenant ID iguais) — já vem `disabled: false` e com
os valores reais.

**Falta um passo manual no Azure**, que a policy não resolve sozinha: adicionar o Redirect URI
deste hub novo no app registration (Azure Portal > App registrations > Authentication):

```
https://oauth-openshift.apps.<domínio-deste-hub>/oauth2callback/AAD
```

Sem isso, a policy fica `Compliant` normalmente (ela só cria Secrets e o `OAuth` CR), mas o
login via AAD falha com `redirect_uri_mismatch` na hora de autenticar de verdade.

---

## Estrutura

Cinco `Placement`s independentes, cada um com seu próprio `PlacementBinding` — de propósito, para
que uma policy possa valer só para Azure, só para VMware, só para o hub, só pros clusters de lab
(qualquer nuvem), ou literalmente pra todo mundo, sem afetar os outros:

| Placement | Seleciona | Quem tá vinculado hoje |
|---|---|---|
| `placement-local-cluster` | só o hub (`local-cluster=true`) | gitops-operator-install, webterminal-install |
| `placement-azure-lab-clusters` | clusters de lab na Azure (`whatsnewsocp-lab=true` + `cloud=Azure`) | *(nenhuma ainda — pronto pra quando divergir)* |
| `placement-vmware-lab-clusters` | clusters de lab na VMware (`whatsnewsocp-lab=true` + `cloud=VMware`) | *(nenhuma ainda — pronto pra quando divergir)* |
| `placement-all-lab-clusters` | qualquer cluster de lab, qualquer nuvem (`whatsnewsocp-lab=true`) | as 8 policies de baseline dos labs (nenhuma é específica de nuvem hoje) |
| `placement-all` | qualquer managed cluster OpenShift, sem filtro (inclui o hub) | policy-oauth-configuration |

Quando uma policy de lab precisar valer só numa nuvem: tira o `subject` de
`07-placementbinding-all-lab-clusters.yaml` e bota num `PlacementBinding` novo apontando pro
`placement-azure-lab-clusters` ou `placement-vmware-lab-clusters`.

Tudo numa pasta só (`policies/`), mesmo padrão flat do `ACM_OCP/Politicas` real — sem separar
placement de policy em diretórios diferentes:

```
acm-hub/
├── README.md
└── policies/                                     # aplicar tudo no hub com oc apply -k
    ├── kustomization.yaml
    ├── 00-namespace.yaml                          # namespace whatsnewsocp-policies
    ├── 01-managedclustersetbinding.yaml           # vincula o clusterset "default" embutido
    ├── 02-placement-local-cluster.yaml
    ├── 03-placementbinding-local-cluster.yaml     # gitops-operator-install, webterminal-install
    ├── 04-placement-azure.yaml                    # sem binding ainda, ver tabela acima
    ├── 05-placement-vmware.yaml                   # sem binding ainda, ver tabela acima
    ├── 06-placement-all-lab-clusters.yaml
    ├── 07-placementbinding-all-lab-clusters.yaml  # as 8 policies de baseline dos labs
    ├── 08-placement-all.yaml
    ├── 09-placementbinding-all.yaml                # policy-oauth-configuration
    ├── policy-gitops-operator-install.yaml         # bootstrap do hub (ver tabela acima)
    ├── policy-webterminal-install.yaml             # bootstrap do hub
    ├── policy-oauth-configuration.yaml             # bootstrap "all" — tem placeholders, ver aviso acima
    └── policy-lab01-...yaml … policy-lab09-...yaml # 1 Policy por lab, YAML puro (sem PolicyGenerator)
```

Sem PolicyGenerator de propósito — time não gosta, e o `ACM_OCP/Politicas` real também não usa
("managed manually for simplicity"). Cada policy de lab é um arquivo próprio, YAML pronto pra
`oc apply`, mesmo padrão de `policy-apps-namespaces.yaml`/`policy-resourcequota-limitrange.yaml`
do repo real — sem exec plugin, sem `--enable-alpha-plugins`.

---

## Passo a passo para quando o hub existir

1. **Instalar o ACM** no cluster novo (operador + `MultiClusterHub`).
2. **Importar** os clusters de lab (ex.: `selma-cold`) como `ManagedCluster` no hub.
   > Nota: `selma-cold` já tem resquícios de um klusterlet antigo quebrado
   > (`open-cluster-management-agent-addon` em CrashLoopBackOff) — provavelmente vai
   > precisar de um `detach`/limpeza antes de reimportar.
3. **Rotular** cada managed cluster de lab para entrar nos Placements certos (rodar contra o
   **hub** — o `local-cluster` já vem rotulado automaticamente pelo próprio ACM, não precisa
   fazer nada pra ele). O label `cloud` (Azure/VMware) já vem populado automaticamente no
   import; só falta o `whatsnewsocp-lab`:
   ```bash
   oc label managedcluster selma-cold whatsnewsocp-lab=true
   oc get managedcluster selma-cold -o jsonpath='{.metadata.labels.cloud}'; echo
   ```
   > Se o cluster for VMware/vSphere, confira o valor real do label `cloud` no comando acima —
   > `05-placement-vmware.yaml` assume `VMware`, ajuste se vier diferente (ex.: `vSphere`).
4. **Aplicar tudo** (namespace, ManagedClusterSetBinding, os 5 Placements, os 3
   PlacementBindings que já têm subject, e as 11 policies — YAML puro, sem plugin nenhum):
   ```bash
   oc apply -k acm-hub/policies
   ```
   As policies de bootstrap (`policy-gitops-operator-install`, `policy-webterminal-install`,
   `policy-oauth-configuration`) vão junto — a de OAuth só some `Compliant` mesmo assim; falta
   o Redirect URI no Entra ID pro login funcionar de fato (ver aviso acima).
5. **Conferir compliance**:
   ```bash
   oc get policy -n whatsnewsocp-policies
   ```
6. Pelo menos **1h antes** de rodar o Lab 9 com a turma, confirme que a policy do PDB já foi
   aplicada (para o alerta ter tempo de virar `firing`).
7. Antes do Passo 5 do Lab 9, aplique o `oc patch ... disabled:true` da seção de aviso acima.

---

## Atualizações futuras

Sempre que um lab novo entrar no repo (ou um existente mudar), a mudança é só:

1. Decidir a linha boilerplate/lição na tabela acima.
2. Criar `policies/policy-labNN-<nome>-baseline.yaml` com o boilerplate embutido como
   `object-templates` (copiar o padrão de um dos labs existentes — não tem geração automática,
   é YAML escrito na mão mesmo).
3. Adicionar o arquivo em `policies/kustomization.yaml` e o nome da policy como `subject` em
   `policies/07-placementbinding-all-lab-clusters.yaml` — ou, se for específica de uma nuvem,
   criar/editar um binding próprio apontando pro `placement-azure-lab-clusters` ou
   `placement-vmware-lab-clusters` (`04-placement-azure.yaml` / `05-placement-vmware.yaml`).
4. Rodar de novo o `oc apply -k acm-hub/policies` no hub.

Se o hub tiver um Channel/Subscription (ou Argo CD Application) apontando direto para este
repositório, esse último passo passa a ser automático a cada commit — aí basta atualizar o
repo, como você pediu.
