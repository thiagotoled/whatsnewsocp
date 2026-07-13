# Exercício 9: Encontrando Problemas Antes de Atualizar o Cluster com `oc adm upgrade recommend`

Neste laboratório, você vai usar o comando `oc adm upgrade recommend` (GA no OpenShift 4.20) para identificar, **antes de iniciar** uma atualização do cluster, condições que podem travar ou atrasar o processo — como um `PodDisruptionBudget` (PDB) configurado de forma restritiva demais, que impede o drain de um nó.

---

## Conceito Rápido

Até então, o `oc adm upgrade` só mostrava a versão atual, os updates disponíveis e o histórico — sem avaliar **riscos conhecidos** antes de você disparar o update.

O `oc adm upgrade recommend` (Tech Preview desde o 4.18, **GA a partir do OpenShift 4.20**) resolve isso com uma funcionalidade de **precheck** embutida, que varre o cluster ativamente em busca de alertas que podem atrapalhar um update tranquilo, por exemplo:

- **Críticos**: `ClusterOperatorDown` (um ClusterOperator indisponível há mais de 10 minutos)
- **Avisos**: `PodDisruptionBudgetAtLimit` (um PDB que pode impedir o drain de nós durante o update)

O fluxo recomendado passa a ser:

1. `oc adm upgrade recommend` → descobre a versão recomendada e roda o precheck
2. Corrige os problemas apontados (ou usa `--accept` para reconhecer riscos já avaliados e aceitos)
3. `oc adm upgrade --to <versão>` → dispara o update de fato

> **Não confundir com `oc adm upgrade status`**: esse é outro comando, ainda em **Technology Preview** (desde o 4.16), usado para acompanhar o **progresso** de um update já em andamento (Control Plane / Worker Pools). O `recommend` atua **antes** do update; o `status` atua **durante**.

---

## Pré-requisitos

- Acesso de administrador ao cluster
- CLI `oc` atualizado (4.20+) autenticado

---

## Passo 1: Linha de Base — Comparar os Dois Comandos

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
oc apply -f UpgradeRecommendPrecheck/ocp-manifests/01-namespace.yaml
oc apply -f UpgradeRecommendPrecheck/ocp-manifests/02-deployment.yaml
```

Confirme que os 3 Pods estão rodando:

```bash
oc get pods -n lab-upgrade-status -o wide
```

---

## Passo 3: Introduzir o Bloqueio — PodDisruptionBudget Restritivo

Aplique um PDB que exige **100% dos Pods disponíveis** (`minAvailable: 100%`) — ou seja, nenhum Pod pode ser removido, nem para drenar um nó durante o update:

```bash
oc apply -f UpgradeRecommendPrecheck/ocp-manifests/03-poddisruptionbudget-blocking.yaml
```

Verifique o PDB criado — note `ALLOWED DISRUPTIONS: 0`:

```bash
oc get pdb -n lab-upgrade-status
```

```
NAME                     MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
nginx-pdb-demo-strict    100%            N/A               0                     5s
```

---

## Passo 4: Detectar o Problema com `oc adm upgrade recommend`

Rode o precheck novamente:

```bash
oc adm upgrade recommend
```

A saída deve reportar um alerta do tipo **Warning** para `PodDisruptionBudgetAtLimit`, apontando o namespace `lab-upgrade-status` e o PDB `nginx-pdb-demo-strict` como risco para o drain de nós durante o update — exatamente o tipo de problema que o comando foi feito para pegar **antes** de você iniciar o update.

---

## Passo 5: Aceitar o Risco (Somente para Fins Didáticos) ou Corrigir

Se o risco já fosse avaliado e considerado aceitável, seria possível prosseguir reconhecendo-o explicitamente:

```bash
oc adm upgrade recommend --version <versão_recomendada> --accept PodDisruptionBudgetAtLimit
```

> **Não** execute o `--accept` seguido de `oc adm upgrade --to` em um cluster real sem necessidade — isso vai de fato disparar o update. Neste lab, o objetivo é apenas visualizar a sintaxe.

O caminho correto aqui, porém, é **corrigir** o PDB. Substitua-o por uma configuração que permite pelo menos 1 Pod indisponível por vez:

```bash
oc apply -f UpgradeRecommendPrecheck/ocp-manifests/04-poddisruptionbudget-fixed.yaml
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

```bash
oc adm upgrade recommend
```

O alerta `PodDisruptionBudgetAtLimit` referente ao namespace `lab-upgrade-status` não deve mais aparecer.

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
