# Exercício 5: Encontrando Problemas Antes de Atualizar o Cluster com `oc adm upgrade recommend`

O `oc adm upgrade recommend` (GA no OpenShift 4.20) identifica, **antes de iniciar** uma atualização, riscos que a Red Hat publicou para a versão-alvo do seu cluster. Este lab explora como o precheck funciona na prática, e por que um `PodDisruptionBudget` (PDB) restritivo, mesmo bloqueando o drain de um nó de verdade, não necessariamente aparece como risco (o motivo é o ponto central deste lab).

---

## Conceito Rápido

Até então, o `oc adm upgrade` só mostrava a versão atual, os updates disponíveis e o histórico, sem avaliar **riscos conhecidos** antes de você disparar o update.

O `oc adm upgrade recommend` (Tech Preview desde o 4.18, **GA a partir do OpenShift 4.20**) resolve isso com uma funcionalidade de **precheck** embutida. Mas é importante entender **como** ela funciona, porque não é um scanner genérico de alertas do seu cluster:

> **Confirmado ao vivo**: o precheck não varre "qualquer alerta firing" e casa por nome. Ele
> compara o estado do seu cluster contra **riscos que a Red Hat já publicou** no grafo de update
> (Cincinnati) para aquela versão-alvo específica. Cada risco é uma expressão PromQL + link de
> bug conhecido, visível em `oc get clusterversion version -o jsonpath='{.status.conditionalUpdates}'`.
> Fabricamos um `PodDisruptionBudgetAtLimit` de verdade (`firing`, inclusive testado também como
> `severity: critical`) e ele **nunca apareceu** no `recommend`, porque não havia nenhum risco
> registrado pela Red Hat usando essa condição para as versões candidatas deste cluster no
> momento do teste. `ClusterOperatorDown`/`PodDisruptionBudgetAtLimit` aparecem como exemplos na
> documentação porque, quando aquele conteúdo foi escrito, existia um risco real publicado
> usando essas condições contra a versão testada, não porque são um par fixo sempre verificado.

Na prática, isso significa que **"no known issues relevant to this cluster" é o resultado mais
comum e esperado** na maior parte do tempo, não um sinal de que o lab não funcionou. O fluxo
recomendado é:

1. `oc adm upgrade recommend` → descobre a versão recomendada e roda o precheck
2. Corrige os problemas apontados (ou usa `--accept` para reconhecer riscos já avaliados e aceitos)
3. `oc adm upgrade --to <versão>` → dispara o update de fato

> **Não confundir com `oc adm upgrade status`**: esse é outro comando, ainda em **Technology Preview** (desde o 4.16), usado para acompanhar o **progresso** de um update já em andamento (Control Plane / Worker Pools). O `recommend` atua **antes** do update; o `status` atua **durante**.

---

## Pré-requisitos

- Acesso de administrador ao cluster
- CLI `oc` atualizado (4.20+) autenticado

> **Confirmado ao vivo**: use o canal `candidate` da sua minor, não `stable` — em clusters ARO o
> canal costuma vir vazio (Azure gerencia upgrade via `az aro update`), e mesmo com `stable`
> configurado, se o cluster já estiver no topo dele o `recommend` só mostra
> `No updates available` sem rodar o precheck. O `candidate` sempre tem uma versão-alvo
> (z-stream) disponível pra demonstrar o precheck de verdade:
> ```bash
> oc adm upgrade channel candidate-4.22   # troque 4.22 pela minor do seu cluster
> ```

---

## Passo 1: Linha de Base (Comparar os Dois Comandos)

Veja a saída tradicional, sem avaliação de riscos:

```bash
oc adm upgrade
```

Agora rode o novo comando com precheck:

```bash
oc adm upgrade recommend
```

A saída inclui um resumo dos updates recomendados e, na sequência, uma seção com os alertas encontrados (ou a confirmação de que nenhum problema foi identificado).

---

## Passo 2: Criar a Carga de Trabalho de Teste

Aplique o namespace e o Deployment que vamos usar para simular o problema:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/05-UpgradeRecommendPrecheck/ocp-manifests/01-namespace.yaml
```

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/05-UpgradeRecommendPrecheck/ocp-manifests/02-deployment.yaml
```

Confirme que os 3 Pods estão rodando:

```bash
oc get pods -n lab-upgrade-status -o wide
```

---

## Passo 3: Introduzir o Bloqueio (PodDisruptionBudget Restritivo)

Aplique um PDB que exige **100% dos Pods disponíveis** (`minAvailable: 100%`), ou seja, nenhum Pod pode ser removido, nem para drenar um nó durante o update:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/05-UpgradeRecommendPrecheck/ocp-manifests/03-poddisruptionbudget-blocking.yaml
```

Verifique o PDB criado. Note `ALLOWED DISRUPTIONS: 0`:

```bash
oc get pdb -n lab-upgrade-status
```

```
NAME                     MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
nginx-pdb-demo-strict    100%            N/A               0                     5s
```

---

## Passo 4: Ver o Alerta Real no Prometheus (não necessariamente no `recommend`)

Rode o precheck de novo:

```bash
oc adm upgrade recommend
```

> **Importante, confirmado ao vivo**: mesmo depois do alerta `PodDisruptionBudgetAtLimit`
> chegar em `firing` de verdade (esperando a 1h do `for:`, ver abaixo), o `recommend` continua
> mostrando `no known issues relevant to this cluster` **a menos que a Red Hat tenha
> atualmente um risco publicado usando essa condição para a sua versão-alvo** (ver o quadro no
> topo deste README). Ou seja: este passo demonstra que o **alerta em si** funciona
> corretamente. A "conexão" entre o alerta e o `recommend` só acontece quando existe um risco
> registrado casando com ele, o que está fora do seu controle como autor do lab.

Pra ver quais riscos **estão** publicados agora pra suas versões candidatas (pode ser nenhum, ou
pode ser algo sem relação nenhuma com PDB):

```bash
oc get clusterversion version -o jsonpath='{.status.conditionalUpdates}' | jq .
```

Cada entrada tem `release.version`, `risks[].name`, `risks[].message` (com link do bug) e
`risks[].matchingRules[].promql`: a expressão exata que a Red Hat usa pra decidir se o risco se
aplica ao seu cluster.

A regra `PodDisruptionBudgetAtLimit` tem `for: 60m`, ou seja, a condição
(`ALLOWED DISRUPTIONS: 0`) precisa persistir por **1 hora** antes do alerta sair de `pending`
para `firing`. Pra confirmar o estado a qualquer momento, consulte o Thanos Querier
diretamente:

```bash
HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')
TOKEN=$(oc create token prometheus-k8s -n openshift-monitoring)

curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://$HOST/api/v1/query?query=ALERTS%7Balertname%3D%22PodDisruptionBudgetAtLimit%22%7D" | jq .
```

Saída esperada, com `alertstate: "pending"` apontando o namespace e o PDB do lab:

```json
{
  "metric": {
    "__name__": "ALERTS",
    "alertname": "PodDisruptionBudgetAtLimit",
    "alertstate": "pending",
    "namespace": "lab-upgrade-status",
    "poddisruptionbudget": "nginx-pdb-demo-strict",
    "severity": "warning"
  }
}
```

Deixe o PDB restritivo aplicado e repita a consulta após ~1 hora: o `alertstate` deve mudar de
`pending` para `firing`. Isso confirma que a detecção do lado do Prometheus funciona como
esperado; **não** espere que isso sozinho faça o `oc adm upgrade recommend` listar o risco (ver
o Passo 4).

---

## Passo 5: Sintaxe do `--accept` e a Boa Prática de Corrigir o PDB

Quando um risco **está** listado (porque a Red Hat publicou um pra sua versão-alvo e a condição
bate com seu cluster), e o time já avaliou e aceita o risco, dá pra prosseguir reconhecendo-o
explicitamente:

```bash
oc adm upgrade recommend --version <versão_recomendada> --accept <NomeDoRisco>
```

> **Não** execute o `--accept` seguido de `oc adm upgrade --to` em um cluster real sem necessidade, isso vai de fato disparar o update. Neste lab, o objetivo é apenas visualizar a sintaxe.

Independente de o `recommend` ter listado o PDB como risco ou não, o caminho correto na prática
é **corrigir** o PDB antes de atualizar: um `minAvailable: 100%` bloqueia o drain do nó de
qualquer forma, com ou sem precheck avisando. Substitua-o por uma configuração que permite pelo
menos 1 Pod indisponível por vez:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/05-UpgradeRecommendPrecheck/ocp-manifests/04-poddisruptionbudget-fixed.yaml
```

Confirme que agora há disrupções permitidas:

```bash
oc get pdb -n lab-upgrade-status
```

```
NAME                     MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
nginx-pdb-demo-strict    N/A             1                 1                     30s
```

---

## Passo 6: Confirmar que o Alerta Desapareceu

Consulte novamente o Thanos Querier: a métrica `ALERTS` para esse namespace/PDB deve desaparecer assim que o Prometheus reavaliar a expressão (a condição `current_healthy == desired_healthy` deixa de ser verdadeira com `maxUnavailable: 1`):

```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://$HOST/api/v1/query?query=ALERTS%7Balertname%3D%22PodDisruptionBudgetAtLimit%22%2Cnamespace%3D%22lab-upgrade-status%22%7D" | jq .
```

Resultado esperado: `"result": []` (vazio). O alerta some assim que o Prometheus reavalia a
condição. Rode o `recommend` mais uma vez só por hábito operacional (ver se algum outro risco
publicado desde o início do lab passou a se aplicar):

```bash
oc adm upgrade recommend
```

---

## Passo 7: Limpeza (Opcional)

```bash
oc delete namespace lab-upgrade-status
```

---

## Referências

- [Red Hat Developer: A guide to the `oc adm upgrade recommend` command](https://developers.redhat.com/articles/2025/10/30/guide-oc-adm-upgrade-recommend-command)
- [OpenShift Container Platform 4.20 Release Notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/release_notes/ocp-4-20-release-notes)
- [Kubernetes: Disruptions e PodDisruptionBudget](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
