# Estratégia de ACM (Advanced Cluster Management) para os Labs

Este diretório contém as `Policy`/`Placement`/`PlacementBinding` do RHACM que rodam **de
verdade** no hub (`local-cluster`, ARO em `rms36u23q91da15275.eastus.aroapp.io`) e em qualquer
managed cluster importado (hoje: `ms35vuo5`). O restante do repositório ([`01-InplacePodverticalscaling/`](../01-InplacePodverticalscaling/README.md),
[`05-SigstoreImagePolicy/`](../05-SigstoreImagePolicy/README.md), etc.) continua igual, cada lab é aplicado manualmente com
`oc apply -f` pelo aluno/instrutor, exatamente como antes; a Policy só cuida do boilerplate.

Sincronizado via Argo CD (`openshift-gitops-acm`, Application `politicasdoacm-local-cluster`)
com `selfHeal: true`. **Qualquer `oc apply` direto no hub que não seja commitado/pushado é
revertido** assim que o Argo reconcilia. Sempre `git commit` + `git push` antes ou logo depois
de aplicar algo aqui manualmente, e force um refresh se precisar ver o efeito na hora:
```bash
oc annotate application.argoproj.io -n openshift-gitops-acm politicasdoacm-local-cluster \
  argocd.argoproj.io/refresh=hard --overwrite
```

---

## Por que usar ACM Policy aqui?

**Reduzir trabalho repetitivo**: parte de cada lab é só "prep" (namespace, deployment,
operador instalado), não é a lição em si. Isso fica pronto no cluster antes da sessão
começar, incluindo em clusters novos assim que são importados.

---

## Regra de ouro: boilerplate vs. lição

**Boilerplate** (pode virar Policy, pré-criado) = tudo que existe só para o aluno ter onde
aplicar a lição, e que não muda o entendimento do conceito se já estiver lá.

**Lição** (fica manual, `oc apply -f` pelo aluno) = o passo que É o conceito sendo ensinado.
Se isso for pré-criado, o aluno perde o "antes/depois" e a lição não acontece.

| Lab | Boilerplate (→ Policy) | Lição (fica manual) |
|---|---|---|
| 1. InplacePodverticalscaling | namespace + deployment | `oc patch --subresource=resize` |
| 2. ExternalSecretsOperator | namespaces (`eso-demo`, `app`) + instalação do operador (falta `ExternalSecretsConfig`, ver nota abaixo) | SecretStore/ExternalSecret (pull e push) |
| 3. UserNamespaces | namespace | os dois Deployments (comparação é a lição) |
| 4. ManagedBootImages | *(nada)* | o único manifesto do lab é a lição inteira (bloqueado em Azure/ARO no 4.20, ver README do lab) |
| 5. SigstoreImagePolicy | namespace + deployment | aplicar/trocar o `ImagePolicy` (chave errada bloqueia, chave real da Red Hat libera) |
| 6. VulnerabilitiesAndCRS | namespace + deployment (imagem RHEL9 real, com CVEs de verdade) — só a Parte 1 (console) | Parte 1: abrir Security → Vulnerabilities no console do OCP. Parte 2 (CRS): *(nada pra pré-criar)* — criar o CRS pela UI com Validity period + Max registrations |

Labs "Enhanced Vulnerability Management Reporting", "Policy Scope com Labels de Cluster/Namespace"
e "Policy para oc debug / pods attach" foram removidos do repositório (eram candidatos a remoção
desde o início, nunca tiveram Policy de boilerplate).

> **Nota lab 2**: [`01-operator-config.yaml`](../02-ExternalSecretsOperator/ocp-manifests/01-operator-config.yaml)/[`02-external-secrets-config.yaml`](../02-ExternalSecretsOperator/ocp-manifests/02-external-secrets-config.yaml) (a instalação do
> operator e o CR `ExternalSecretsConfig`) ainda não têm policy, hoje é aplicado manualmente
> seguindo o README do lab. O `ExternalSecretsConfig` é fácil de esquecer (o operator sobe mas
> o controller de verdade só nasce depois dele). Confirmado ao vivo, ver
> [`02-ExternalSecretsOperator/README.md`](../02-ExternalSecretsOperator/README.md).

Além do boilerplate por lab, existem policies de **bootstrap do próprio hub** (não são de
nenhum lab específico), trazidas do repo real `ACM_OCP/Politicas` e adaptadas:

| Policy | O que faz | Onde roda |
|---|---|---|
| `policy-gitops-operator-install` | Instala o OpenShift GitOps operator | `local-cluster` (o hub) |
| `policy-webterminal-install` | Instala o Web Terminal operator | **`all`**: todo managed cluster OpenShift |
| `policy-oauth-configuration` | Configura OAuth (HTPasswd + Entra ID/AAD via OIDC) | **`azure`**: qualquer managed cluster OpenShift na Azure, hub incluído |
| `policy-cluster-admin-rbac` | `ClusterRoleBinding` de `cluster-admin` pro grupo Entra ID (Object ID `6a758b5d-bbfb-498c-ae13-0cea9803de29`, mesmo grupo do oauth) + user `admin` | **`azure`** |
| `policy-acs-operator-install` | Instala o `rhacs-operator`, sem CR nenhum (compartilhado entre Central e SecuredCluster) | **`all`** |
| `policy-acs-central` | Namespace `stackrox` + CR `Central` | `local-cluster` (só o hub roda Central) |
| `policy-acs-secured-cluster` | Namespace + CRS (via `fromSecret`) + CR `SecuredCluster` + plugin `advanced-cluster-security` no console | **`all`**: hub incluído (o hub também monitora a si mesmo) |

---

## ⚠️ Lição aprendida: `Compliant` não significa "pods saudáveis"

Achado real ao importar o primeiro managed cluster (`ms35vuo5`): `policy-acs-secured-cluster`
ficou `Compliant` imediatamente, mas **todos** os pods do namespace `stackrox` ficaram travados
em `ContainerCreating`/`CrashLoopBackOff` por mais de 1h. Causa: o `SecuredCluster` não tinha
`spec.centralEndpoint`, então usava o default `central.stackrox.svc:443`, um DNS que só
resolve quando o Central roda no **mesmo** cluster. `ConfigurationPolicy` só valida que o objeto
bate com o spec desejado, não que os pods que esse objeto gera estão de pé.

**Sempre que uma Policy cria um objeto que por sua vez cria pods** (Operator CRs, principalmente),
`Compliant` é necessário mas não suficiente. Confirme também com `oc get pods -n <namespace>`
no managed cluster, não só o status da Policy no hub.

---

## ⚠️ Cuidado com secrets reais que NÃO estão no git

Este repositório é **público**. Os seguintes valores são aplicados manualmente no namespace
`whatsnewsocp-policies` do hub e referenciados pelas Policies via hub template `fromSecret`,
nunca commitados:

| Secret (namespace `whatsnewsocp-policies` no hub) | Usado por | Onde reaplicar se precisar |
|---|---|---|
| `htpasswd-2cr76` | `policy-oauth-configuration` | `oc apply -f ~/secret-htpasswd.yaml` (fora do repo) |
| `aad-client-secret` | `policy-oauth-configuration` | `oc apply -f ~/secret-aad-client.yaml` (fora do repo) |
| `cluster-registration-secret` | `policy-acs-secured-cluster` | gerar novo CRS em Central > Clusters > Cluster registration secrets, `oc apply` no hub |

Se algum desses secrets sumir (ex.: reset do namespace `whatsnewsocp-policies`), as policies que
dependem deles ficam `NonCompliant` até você reaplicar. O `fromSecret` não falha
silenciosamente, mas também não recria o secret-fonte sozinho.

---

## ⚠️ Cuidado com a `policy-oauth-configuration` (Redirect URI do Entra ID)

Essa policy reaproveita o **mesmo app registration** do Entra ID usado em `ACM_OCP/Politicas`
(`openshift-oauth-jdasilve`, appId `ecb2c027-2a5f-4324-9e05-3aa819ab351e`) em todo cluster Azure,
hub e qualquer managed cluster importado.

**Cada cluster novo precisa do próprio Redirect URI adicionado no app registration**. A policy
não resolve isso sozinha (ela só cria Secrets e o `OAuth` CR). Sem o Redirect URI, a policy fica
`Compliant` normalmente, mas o login via AAD falha com `redirect_uri_mismatch` na hora de
autenticar de verdade:

```bash
# Ver as URIs atuais (não sobrescrever nenhuma)
az ad app show --id ecb2c027-2a5f-4324-9e05-3aa819ab351e --query "web.redirectUris" -o json

# Adicionar a URI do cluster novo à lista e aplicar via Graph (az ad app update não tem
# flag de redirect-uri pra Web platform)
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications(appId='ecb2c027-2a5f-4324-9e05-3aa819ab351e')" \
  --headers "Content-Type=application/json" \
  --body '{"web": {"redirectUris": [<lista completa, antiga + nova>]}}'
```

URI do cluster: `https://oauth-openshift.apps.<domínio-do-cluster>/oauth2callback/AAD`

---

## Estrutura

Seis `Placement`s independentes, cada um com seu próprio `PlacementBinding`, de propósito, para
que uma policy possa valer só para Azure (hub incluído), só pros clusters de lab de uma nuvem
específica, só pros clusters de lab (qualquer nuvem), só para o hub, ou literalmente pra todo
mundo, sem afetar os outros:

| Placement | Seleciona | Quem tá vinculado hoje |
|---|---|---|
| `placement-local-cluster` | só o hub (`local-cluster=true`) | gitops-operator-install, policy-acs-central |
| `placement-azure` | qualquer managed cluster OpenShift na Azure, **hub incluído** (`cloud=Azure` + `vendor=OpenShift`, sem exigir `whatsnewsocp-lab`) | policy-oauth-configuration, policy-cluster-admin-rbac |
| `placement-vmware-lab-clusters` | clusters de **lab** na VMware (`whatsnewsocp-lab=true` + `cloud=VMware`) | *(nenhuma ainda, pronto pra quando divergir)* |
| `placement-all-lab-clusters` | qualquer cluster de lab, qualquer nuvem (`whatsnewsocp-lab=true`) | as 5 policies de baseline dos labs (nenhuma é específica de nuvem hoje) |
| `placement-all` | qualquer managed cluster OpenShift, sem filtro (inclui o hub) | webterminal-install, policy-acs-operator-install, policy-acs-secured-cluster |

> **Assimetria de propósito:** `placement-azure` NÃO exige `whatsnewsocp-lab` (cobre o hub, que
> é Azure); `placement-vmware-lab-clusters` exige (só clusters de lab VMware, o hub não é
> VMware). Se um dia precisar de "só clusters de **lab** que sejam Azure" (sem o hub), crie um
> placement novo em vez de reusar o `placement-azure`.

Quando uma policy de lab precisar valer só numa nuvem: tira o `subject` de
[`07-placementbinding-all-lab-clusters.yaml`](policies/07-placementbinding-all-lab-clusters.yaml) e bota num `PlacementBinding` novo apontando pro
`placement-vmware-lab-clusters` (ou um placement novo de "lab clusters Azure", ver nota acima).

Tudo numa pasta só ([`policies/`](policies/)), mesmo padrão flat do `ACM_OCP/Politicas` real, sem separar
placement de policy em diretórios diferentes:

```
acm-hub/
├── README.md
└── policies/                                     # aplicar tudo no hub com oc apply -k
    ├── kustomization.yaml
    ├── 00-namespace.yaml                          # namespace whatsnewsocp-policies
    ├── 01-managedclustersetbinding.yaml           # vincula o clusterset "default" embutido
    ├── 02-placement-local-cluster.yaml
    ├── 03-placementbinding-local-cluster.yaml     # gitops-operator-install, policy-acs-central
    ├── 04-placement-azure.yaml                    # placement-azure (hub incluído)
    ├── 05-placement-vmware.yaml                   # sem binding ainda, ver tabela acima
    ├── 06-placement-all-lab-clusters.yaml
    ├── 07-placementbinding-all-lab-clusters.yaml  # as 5 policies de baseline dos labs
    ├── 08-placement-all.yaml
    ├── 09-placementbinding-all.yaml                # webterminal, policy-acs-operator-install, policy-acs-secured-cluster
    ├── 10-placementbinding-azure.yaml              # policy-oauth-configuration, policy-cluster-admin-rbac
    ├── policy-gitops-operator-install.yaml         # bootstrap do hub (ver tabela acima)
    ├── policy-webterminal-install.yaml             # bootstrap "all"
    ├── policy-oauth-configuration.yaml             # bootstrap "azure", usa fromSecret, ver aviso acima
    ├── policy-cluster-admin-rbac.yaml              # bootstrap "azure"
    ├── policy-acs-operator-install.yaml            # bootstrap "all"
    ├── policy-acs-central.yaml                     # bootstrap "local-cluster"
    ├── policy-acs-secured-cluster.yaml             # bootstrap "all", usa fromSecret, ver aviso acima
    ├── policy-lab01.yaml
    ├── policy-lab02.yaml
    ├── policy-lab03.yaml
    ├── policy-lab05.yaml
    └── policy-lab06.yaml                           # Parte 1 (console); Parte 2 (CRS) não tem policy — só geração via UI
```

Sem PolicyGenerator de propósito: time não gosta, e o `ACM_OCP/Politicas` real também não usa
("managed manually for simplicity"). Cada policy de lab é um arquivo próprio, YAML pronto pra
`oc apply`, mesmo padrão de `policy-apps-namespaces.yaml`/`policy-resourcequota-limitrange.yaml`
do repo real, sem exec plugin, sem `--enable-alpha-plugins`.

> **Nomes curtos de propósito:** o webhook do ACM rejeita uma Policy se `namespace + name`
> passar de 62 caracteres. Com o namespace `whatsnewsocp-policies` (21 chars), nomes descritivos
> tipo `policy-lab01-inplace-pod-vertical-scaling-baseline` estouram o limite, por isso os
> arquivos de lab usam só `policy-labNN` (a descrição já está no comentário no topo do arquivo).

---

## Importando um cluster novo

1. **Importar** o cluster como `ManagedCluster` no hub (via console do ACM ou `clusteradm`).
2. **Rotular** o cluster pra entrar nos Placements certos (rodar contra o **hub**, o
   `local-cluster` já vem rotulado automaticamente, não precisa fazer nada pra ele). Os labels
   `cloud`/`vendor` já vêm populados automaticamente no import; só falta o `whatsnewsocp-lab`:
   ```bash
   oc label managedcluster <nome-do-cluster> whatsnewsocp-lab=true
   oc get managedcluster <nome-do-cluster> -o jsonpath='{.metadata.labels.cloud}'; echo
   ```
   > Se o cluster for VMware/vSphere, confira o valor real do label `cloud` no comando acima,
   > [`05-placement-vmware.yaml`](policies/05-placement-vmware.yaml) assume `VMware`, ajuste se vier diferente (ex.: `vSphere`).
3. **Conferir compliance** (pode levar alguns minutos pra propagar):
   ```bash
   oc get policy -n <nome-do-cluster>
   ```
   Pra qualquer policy que instale um Operator com CR (hoje só o ACS), confirme também os pods
   de verdade no managed cluster, ver aviso "`Compliant` não significa pods saudáveis" acima.
4. **Redirect URI do Entra ID**: se o cluster for Azure, adicione o Redirect URI dele no app
   registration (ver aviso acima). Sem isso o login AAD falha mesmo com a policy `Compliant`.

---

## Atualizações futuras

Sempre que um lab novo entrar no repo (ou um existente mudar), a mudança é só:

1. Decidir a linha boilerplate/lição na tabela acima.
2. Criar `policies/policy-labNN.yaml` com o boilerplate embutido como `object-templates`
   (copiar o padrão de um dos labs existentes, não tem geração automática, é YAML escrito na
   mão mesmo). Nome curto (`policy-labNN`, sem sufixo descritivo) por causa do limite de 62
   caracteres, ver nota acima.
3. Adicionar o arquivo em [`policies/kustomization.yaml`](policies/kustomization.yaml) e o nome da policy como `subject` em
   [`policies/07-placementbinding-all-lab-clusters.yaml`](policies/07-placementbinding-all-lab-clusters.yaml), ou, se for específica de uma nuvem,
   criar/editar um binding próprio apontando pro `placement-vmware-lab-clusters`
   ([`05-placement-vmware.yaml`](policies/05-placement-vmware.yaml)) ou, pra Azure, um placement novo de "lab clusters Azure" (o
   `placement-azure` em [`04-placement-azure.yaml`](policies/04-placement-azure.yaml) é genérico, inclui o hub, ver nota acima).
4. `git commit` + `git push`: o Argo CD (`politicasdoacm-local-cluster`) sincroniza sozinho.
   Se precisar ver o efeito na hora em vez de esperar o próximo poll, force o refresh (comando
   no topo deste README).
