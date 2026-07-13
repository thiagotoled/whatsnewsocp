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
| 8. ComplianceTailoredProfilesScheduling | namespace + operator + TailoredProfile | agendar via UI RHACS + validar ScanSettingBinding |
| 9. UpgradeRecommendPrecheck | namespace + deployment **+ PDB restritivo (ver aviso abaixo)** | corrigir o PDB e ver o precheck refletir |

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

## Estrutura

```
acm-hub/
├── README.md
├── placement/                        # aplicar direto no hub, uma vez (oc apply -k)
│   ├── 00-namespace.yaml             # namespace whatsnewsocp-policies
│   ├── 01-managedclusterset.yaml     # ManagedClusterSet whatsnewsocp-labs
│   ├── 02-managedclustersetbinding.yaml
│   └── 03-placement.yaml             # seleciona clusters com label whatsnewsocp-lab=true
└── policies/                         # gerado via kustomize + policy-generator-plugin
    ├── kustomization.yaml
    └── policy-generator-config.yaml  # 1 Policy de baseline por lab (ver tabela acima)
```

---

## Passo a passo para quando o hub existir

1. **Instalar o ACM** no cluster novo (operador + `MultiClusterHub`).
2. **Importar** os clusters de lab (ex.: `selma-cold`) como `ManagedCluster` no hub.
   > Nota: `selma-cold` já tem resquícios de um klusterlet antigo quebrado
   > (`open-cluster-management-agent-addon` em CrashLoopBackOff) — provavelmente vai
   > precisar de um `detach`/limpeza antes de reimportar.
3. **Rotular** cada managed cluster para entrar no ManagedClusterSet e no Placement (rodar
   contra o **hub**):
   ```bash
   oc label managedcluster selma-cold cluster.open-cluster-management.io/clusterset=whatsnewsocp-labs
   oc label managedcluster selma-cold whatsnewsocp-lab=true
   ```
4. **Aplicar o placement** (namespace + ManagedClusterSet + binding + Placement):
   ```bash
   oc apply -k acm-hub/placement
   ```
5. **Gerar e aplicar as policies** (precisa do `policy-generator-plugin` como exec plugin do
   kustomize — ver [stolostron/policy-generator-plugin](https://github.com/stolostron/policy-generator-plugin)):
   ```bash
   kustomize build --enable-alpha-plugins acm-hub/policies | oc apply -f -
   ```
6. **Conferir compliance**:
   ```bash
   oc get policy -n whatsnewsocp-policies
   ```
7. Pelo menos **1h antes** de rodar o Lab 9 com a turma, confirme que a policy do PDB já foi
   aplicada (para o alerta ter tempo de virar `firing`).
8. Antes do Passo 5 do Lab 9, aplique o `oc patch ... disabled:true` da seção de aviso acima.

---

## Atualizações futuras

Sempre que um lab novo entrar no repo (ou um existente mudar), a mudança é só:

1. Decidir a linha boilerplate/lição na tabela acima.
2. Adicionar/editar a entry correspondente em `policies/policy-generator-config.yaml`
   (apontando pros manifests que já existem no lab — sem duplicar YAML).
3. Rodar de novo o `kustomize build ... | oc apply -f -` no hub.

Se o hub tiver um Channel/Subscription (ou Argo CD Application) apontando direto para este
repositório, esse último passo passa a ser automático a cada commit — aí basta atualizar o
repo, como você pediu.
