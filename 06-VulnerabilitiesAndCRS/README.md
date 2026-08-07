# Exercício 7: Vulnerabilidades no Console e Mais Controle no CRS (RHACS 4.11)

Duas novidades do RHACS 4.11 que vivem na mesma área — segurança operacional do dia a dia,
uma no console do OpenShift, outra na UI do Central:

- **Parte 1 (Console)**: ver vulnerabilidades de workload **dentro do console do OpenShift**,
  sem sair dele nem precisar de login separado no Central.
- **Parte 2 (CRS)**: gerar um **Cluster Registration Secret** com os controles novos de
  validade e limite de registros, entendendo por que isso importa pra quem gerencia o registro
  de clusters no dia a dia.

---

## Parte 1: Vulnerabilidades de Workload Direto no Console do OpenShift

Você vai ver os dados de vulnerabilidade do RHACS (Central + Scanner V4) aparecerem **dentro do
próprio console web do OpenShift** — via o `ConsolePlugin` `advanced-cluster-security`, entregue
pelo `rhacs-operator` e habilitado no `Console/cluster` (`operator.openshift.io/v1`).

### Conceito Rápido

O RHACS já expõe vulnerabilidades de imagem há muito tempo na UI própria do Central
(**Vulnerability Management → Workload CVEs**). O que muda aqui é **onde** você vê esse dado: o
`rhacs-operator` publica um `ConsolePlugin` que, uma vez habilitado, adiciona um item
**Security → Vulnerabilities** direto no menu lateral do console do OpenShift — a mesma tela que
você já usa pra Workloads, Networking, Storage etc.

Isso só funciona depois de dois pré-requisitos ficarem prontos:

1. O `SecuredCluster` rodando no cluster (Sensor conectado ao Central, escaneando as imagens).
2. O plugin habilitado em `Console/cluster`:
   ```yaml
   apiVersion: operator.openshift.io/v1
   kind: Console
   metadata:
     name: cluster
   spec:
     plugins:
       - advanced-cluster-security
   ```
   Sem isso, o operator instala o `ConsolePlugin` mas ele fica **Disabled** em
   **Administration → Cluster Settings → Configuration → Console → Console plugins**, e o item
   de menu nem aparece.

Neste repositório os dois já vêm resolvidos pela automação em [`acm-hub/`](../acm-hub/README.md)
(`policy-acs-operator-install`, `policy-acs-secured-cluster` — esta última inclui o
`policy-acs-console-plugin`). A lição desta parte é só a exploração da tela.

### Pré-requisitos

- `policy-acs-secured-cluster` `Compliant` no cluster (ou `SecuredCluster` + plugin habilitados
  manualmente) — confirme com:
  ```bash
  oc get securedcluster -n stackrox
  oc get console.operator.openshift.io cluster -o jsonpath='{.spec.plugins}'
  ```
  `advanced-cluster-security` precisa aparecer na lista.
- Acesso ao console web do OpenShift.

### Passo 1: Confirmar que o Plugin Está Carregado

**Administration → Cluster Settings → Configuration → Console → Console plugins** — confirme
`advanced-cluster-security` como **Enabled**. Se acabou de habilitar via policy, o console pode
levar um ou dois minutos pra recarregar o bundle do plugin (um refresh da aba resolve).

### Passo 2: Gerar um Workload com CVEs Reais

Uma pegadinha ao montar este lab: imagens de distro **EOL** (testamos com `nginx:1.14.0`, base
Debian 9) sempre voltam **0 CVEs** do Scanner V4 — a Debian Security Tracker parou de publicar
dados pra releases fora de suporte, então não tem CVE pra casar com os pacotes, mesmo a imagem
sendo antiga e cheia de bugs conhecidos. Pra ter dado real e reprodutível, este lab usa uma
imagem **RHEL9/UBI** (ainda coberta pelo feed da Red Hat) — no caso, a mesma imagem do console
do `multicluster-engine` já em uso no seu hub ACM, escaneada ao vivo com **178 CVEs / 25
fixable**:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/06-VulnerabilitiesAndCRS/ocp-manifests/01-namespace.yaml
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/06-VulnerabilitiesAndCRS/ocp-manifests/02-deployment.yaml
```

O `command: ["sleep", "infinity"]` é só pra não tentar rodar o binário do console do MCE de
verdade — a gente só precisa da imagem no nó pro Scanner analisar.

Confirme que subiu:

```bash
oc get pods -n lab-console-vulnerabilities
```

### Passo 3: Esperar o Sensor Escanear

O Sensor detecta o novo `Deployment` e reporta a imagem pro Central em segundos; o scan de
vulnerabilidade (Scanner V4) normalmente termina em menos de um minuto. Sem acesso à UI do
Central, dá pra confirmar via API também (usando a senha do secret `central-htpasswd`):

```bash
ROUTE=$(oc get route central -n stackrox -o jsonpath='{.spec.host}')
PASS=$(oc get secret central-htpasswd -n stackrox -o jsonpath='{.data.password}' | base64 -d)
curl -sk -u admin:"$PASS" "https://$ROUTE/v1/images?query=Namespace%3Alab-console-vulnerabilities"
```

Saída esperada (resumida) — `cves` deixa de ser `0`:

```json
{"images":[{"name":"registry.redhat.io/multicluster-engine/console-mce-rhel9@sha256:da19...","components":205,"cves":178,"fixableCves":25,...}]}
```

### Passo 4: Explorar no Console do OpenShift

No menu lateral, **Security → Vulnerabilities**. Você vai ver a tela **Workload vulnerabilities**,
com **Project: All Projects** por padrão.

1. Troque o filtro de projeto pra `lab-console-vulnerabilities` (ou filtre por `Name` contendo o
   CVE que você quiser).
2. Repare nas colunas: **Images by severity** (quantas imagens são afetadas, por severidade —
   ícones de bandeira/seta), **Top CVSS**, **Top NVD CVSS**, **EPSS probability** (probabilidade
   de exploração ativa, dado do FIRST.org), **First discovered** (nesse cluster) e **Published**
   (data oficial do CVE).
3. Clique em qualquer CVE com severidade Important ou Critical pra ver o painel de detalhe:
   descrição, versão corrigida (`Fixed in`), e quais imagens/deployments especificamente são
   afetados.
4. Alterne entre as abas **CVEs**, **Images** e **Deployments** no topo da tabela — a mesma
   navegação por perspectiva que existe na UI do Central, só que embutida no console do OCP.

O ponto central desta parte: um desenvolvedor com acesso só ao seu projeto no OpenShift agora
enxerga as CVEs do que ele mesmo faz deploy, **sem precisar de login separado no Central** nem
de uma role específica do RHACS — é RBAC do próprio OpenShift.

### Limpeza (Parte 1)

```bash
oc delete namespace lab-console-vulnerabilities
```

Isso não desfaz o plugin habilitado nem o `SecuredCluster` — eles ficam pra outros labs de ACS
deste repositório. Se quiser reverter só o plugin, edite `spec.plugins` no `Console/cluster` e
remova `advanced-cluster-security` (não recomendado enquanto a automação em `acm-hub/` continuar
gerenciando essa policy — ela reaplicaria em segundos).

---

## Parte 2: Mais Controle sobre o Cluster Registration Secret (CRS)

Você vai gerar um **Cluster Registration Secret (CRS)** pela **UI do Central** usando os dois
controles novos do RHACS 4.11 — **validade** e **limite de registros** — e ver como isso muda o
que aparece na lista de secrets. Esta parte é só de **geração/entendimento**: você não vai
aplicar o CRS gerado em nenhum cluster. O registro dos clusters deste hub já é feito pela
[`policy-acs-secured-cluster`](../acm-hub/README.md), que usa um CRS próprio aplicado
manualmente (fora do git, por segurança).

### Conceito Rápido

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

### Pré-requisitos

- RHACS 4.11 (Central) rodando e acessível pela UI.
- Permissão de **Admin** (ou role com acesso a `Administration`).

### Passo 1: Ver o CRS Já Existente Neste Hub

**Platform Configuration → Clusters → aba "Cluster registration secrets"** (ou o link
**Cluster registration secrets** no topo da tela **Clusters**).

Você vai ver o `acs_registration_clusters` — o CRS que este repositório usa pra registrar
clusters via `policy-acs-secured-cluster`, criado sem os controles novos:

| Name | Created by | Expires in | Registrations |
|---|---|---|---|
| acs_registration_clusters | jdasilve@redhat.com | *\<tempo restante\>* | Unlimited |

Esse é exatamente o padrão "antigo" que o 4.11 permite evitar: validade longa, sem limite de
quantos clusters podem se registrar com ele.

### Passo 2: Gerar um CRS com os Controles Novos

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

### Passo 3: Comparar na Lista

De volta em **Cluster registration secrets**, o novo `lab-crs-scoped-demo` aparece ao lado do
antigo, agora com validade e limite visíveis — dá pra comparar os dois lado a lado:

| Name | Expires in | Registrations |
|---|---|---|
| acs_registration_clusters | *\<tempo restante\>* | Unlimited |
| lab-crs-scoped-demo | ~1 hour | 0 / 1 |

(O `0 / 1` mostra quantos registros já foram usados dos 1 permitido — isso vem do
`registrationsCompleted` que o Central rastreia por CRS, o mesmo dado que alimenta essa coluna.)

### Passo 4: Inspecionar o YAML Baixado

Abra o arquivo baixado — é o mesmo formato `Secret` (`crs.platform.stackrox.io/*` em
`annotations`, campo `data.crs` em base64) que você aplicaria num managed cluster. Note nos
`annotations`:

- `crs.platform.stackrox.io/expires-at` — reflete a validade que você escolheu no Passo 2.
- `crs.platform.stackrox.io/id` — o identificador único, o mesmo que aparece na lista da UI e
  que seria usado numa eventual revogação.

De novo: esta é só uma parte de geração. **Não aplique este secret** em nenhum `SecuredCluster`
— ele existe só pra você ver o resultado dos controles novos.

### Passo 5: Revogar (Fechar o Ciclo)

Mesmo com validade curta e limite de 1 registro, dá pra invalidar o CRS antes mesmo dele expirar
ou ser usado — útil se você gerou por engano ou o processo que ia usá-lo foi cancelado. Na linha
do `lab-crs-scoped-demo`, use o menu de ações (ícone **⋮**) e revogue o secret. Confirme que ele
some da lista (ou aparece como revogado, dependendo da versão da UI) — qualquer tentativa de
registro com o YAML baixado no Passo 2 passa a falhar a partir daqui.

---

## Referências

- [Advanced Cluster Security for Kubernetes 4.11 Release Notes](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11/html/release_notes/index)
- [Viewing security information in the OpenShift web console — RHACS docs](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11)
- [Console \[operator.openshift.io/v1\] — Config APIs — OpenShift](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/config_apis/console-operator-openshift-io-v1)
- [Cluster registration secrets — RHACS 4.11 docs](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11)
- [`policy-acs-secured-cluster`](../acm-hub/policies/policy-acs-secured-cluster.yaml) — como este
  repositório usa um CRS (sem os limites deste lab, de propósito, pra registrar quantos clusters
  forem importados) via ACM Policy.
