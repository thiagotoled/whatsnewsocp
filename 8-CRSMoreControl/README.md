# Exercício 8: Mais Controle sobre o Cluster Registration Secret (CRS)

Neste laboratório, você vai gerar um **Cluster Registration Secret (CRS)** pela **UI do
Central** usando os dois controles novos do RHACS 4.11 — **validade** e **limite de
registros** — e ver como isso muda o que aparece na lista de secrets. Este lab é só de
**geração/entendimento**: você não vai aplicar o CRS gerado em nenhum cluster. O registro dos
clusters deste hub já é feito pela [`policy-acs-secured-cluster`](../acm-hub/README.md), que usa
um CRS próprio aplicado manualmente (fora do git, por segurança).

---

## Conceito Rápido

O CRS existe desde o RHACS 4.10, substituindo o **init-bundle** como forma de registrar
`SecuredCluster`s no Central — a vantagem sobre o init-bundle é ser **reutilizável em qualquer
número de clusters** (um init-bundle era gerado por cluster). Isso é o que torna o registro
automatizável via Policy (ver [Exercício ACM/ACS](../acm-hub/README.md)).

Só que "reutilizável em qualquer número de clusters, pra sempre" também é um problema de
segurança: um CRS vazado vira uma credencial de longa duração sem limite de uso. O RHACS foi
apertando isso em duas rodadas:

- **4.9**: mudou a validade **padrão** de 1 ano pra **1 hora**.
- **4.11**: adiciona dois controles explícitos na hora de gerar o CRS —
  - **Validity period**: `Default` (o padrão do servidor, hoje 24h), `By date` (data exata de
    expiração) ou `By hours` (quantidade de horas a partir de agora).
  - **Max registrations**: quantos clusters distintos podem usar esse secret pra se registrar
    (1–100, ou em branco = ilimitado — o comportamento antigo).

Na prática: em vez de um CRS "mestre" que qualquer engenheiro/pipeline usa pra sempre (como o
`acs_registration_clusters` já existente neste hub — veja o Passo 1), agora dá pra emitir um CRS
**de uso único, de validade curta**, por exemplo pra um pipeline de CI que provisiona um cluster
efêmero, sem deixar uma credencial reutilizável sobrando depois.

---

## Pré-requisitos

- RHACS 4.11 (Central) rodando e acessível pela UI.
- Permissão de **Admin** (ou role com acesso a `Administration`).

---

## Passo 1: Ver o CRS Já Existente Neste Hub

**Platform Configuration → Clusters → aba "Cluster registration secrets"** (ou o link
**Cluster registration secrets** no topo da tela **Clusters**).

Você vai ver o `acs_registration_clusters` — o CRS que este repositório usa pra registrar
clusters via `policy-acs-secured-cluster`, criado sem os controles novos:

| Name | Created by | Expires in | Registrations |
|---|---|---|---|
| acs_registration_clusters | jdasilve@redhat.com | 5 months | Unlimited |

Esse é exatamente o padrão "antigo" que o 4.11 permite evitar: validade longa, sem limite de
quantos clusters podem se registrar com ele.

---

## Passo 2: Gerar um CRS com os Controles Novos

Clique em **Create cluster registration secret**. Preencha:

- **Name**: `lab-crs-scoped-demo`
- **Validity period**: selecione **By hours** e informe `1` (só precisa valer o tempo do lab).
  Repare que **By date** também está disponível, pra quando você sabe exatamente até quando o
  CRS deve valer (ex.: a janela de um projeto).
- **Max registrations**: `1` — só um cluster vai conseguir se registrar com este secret, mesmo
  que ele vaze antes de expirar.

Antes de confirmar, note o aviso:

> **Download YAML file** — You can download the YAML file only once, when you create a cluster
> registration secret. Store the YAML file securely because it contains secrets.

Isso também é deliberado: o Central não guarda o conteúdo pra você baixar de novo depois — só os
metadados (nome, validade, quantos já registraram). Se perder o arquivo, a única saída é revogar
e gerar outro.

Clique **Download**. Guarde o arquivo só pra inspecionar no próximo passo — **não vá aplicá-lo**
em cluster nenhum.

---

## Passo 3: Comparar na Lista

De volta em **Cluster registration secrets**, o novo `lab-crs-scoped-demo` aparece ao lado do
antigo, agora com validade e limite visíveis — dá pra comparar os dois lado a lado:

| Name | Expires in | Registrations |
|---|---|---|
| acs_registration_clusters | 5 months | Unlimited |
| lab-crs-scoped-demo | ~1 hour | 0 / 1 |

(O `0 / 1` mostra quantos registros já foram usados dos 1 permitido — isso vem do
`registrationsCompleted` que o Central rastreia por CRS, o mesmo dado que alimenta essa coluna.)

---

## Passo 4: Inspecionar o YAML Baixado

Abra o arquivo baixado — é o mesmo formato `Secret` (`crs.platform.stackrox.io/*` em
`annotations`, campo `data.crs` em base64) que você aplicaria num managed cluster. Note nos
`annotations`:

- `crs.platform.stackrox.io/expires-at` — reflete a validade que você escolheu no Passo 2.
- `crs.platform.stackrox.io/id` — o identificador único, o mesmo que aparece na lista da UI e
  que seria usado numa eventual revogação.

De novo: este é só um exercício de geração. **Não aplique este secret** em nenhum
`SecuredCluster` — ele existe só pra você ver o resultado dos controles novos.

---

## Passo 5: Revogar (Fechar o Ciclo)

Mesmo com validade curta e limite de 1 registro, dá pra invalidar o CRS antes mesmo dele expirar
ou ser usado — útil se você gerou por engano ou o processo que ia usá-lo foi cancelado. Na linha
do `lab-crs-scoped-demo`, use o menu de ações (ícone **⋮**) e revogue o secret. Confirme que ele
some da lista (ou aparece como revogado, dependendo da versão da UI) — qualquer tentativa de
registro com o YAML baixado no Passo 2 passa a falhar a partir daqui.

---

## Referências

- [Cluster registration secrets — RHACS 4.11 docs](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11)
- [`policy-acs-secured-cluster`](../acm-hub/policies/policy-acs-secured-cluster.yaml) — como este
  repositório usa um CRS (sem os limites deste lab, de propósito, pra registrar quantos clusters
  forem importados) via ACM Policy.
