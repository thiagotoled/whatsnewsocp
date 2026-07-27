# Exercício 10: Vulnerabilidades de Workload Direto no Console do OpenShift

Neste laboratório, você vai ver os dados de vulnerabilidade do RHACS (Central + Scanner V4)
aparecerem **dentro do próprio console web do OpenShift**, sem precisar sair dele nem ter
credenciais separadas do Central — via o `ConsolePlugin` `advanced-cluster-security`, entregue
pelo `rhacs-operator` e habilitado no `Console/cluster` (`operator.openshift.io/v1`).

---

## Conceito Rápido

O RHACS já expõe vulnerabilidades de imagem há muito tempo na UI própria do Central
(**Vulnerability Management → Workload CVEs**, ver [Exercício 5](../5-VulnerabilityManagementReporting/README.md)).
O que muda aqui é **onde** você vê esse dado: o `rhacs-operator` publica um `ConsolePlugin`
que, uma vez habilitado, adiciona um item **Security → Vulnerabilities** direto no menu lateral
do console do OpenShift — a mesma tela que você já usa pra Workloads, Networking, Storage etc.

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
`policy-acs-console-plugin`). A lição deste lab é só a exploração da tela.

---

## Pré-requisitos

- `policy-acs-secured-cluster` `Compliant` no cluster (ou `SecuredCluster` + plugin habilitados
  manualmente) — confirme com:
  ```bash
  oc get securedcluster -n stackrox
  oc get console.operator.openshift.io cluster -o jsonpath='{.spec.plugins}'
  ```
  `advanced-cluster-security` precisa aparecer na lista.
- Acesso ao console web do OpenShift.

---

## Passo 1: Confirmar que o Plugin Está Carregado

**Administration → Cluster Settings → Configuration → Console → Console plugins** — confirme
`advanced-cluster-security` como **Enabled**. Se acabou de habilitar via policy, o console pode
levar um ou dois minutos pra recarregar o bundle do plugin (um refresh da aba resolve).

---

## Passo 2: Gerar um Workload com CVEs Reais

Uma pegadinha ao montar este lab: imagens de distro **EOL** (testamos com `nginx:1.14.0`, base
Debian 9) sempre voltam **0 CVEs** do Scanner V4 — a Debian Security Tracker parou de publicar
dados pra releases fora de suporte, então não tem CVE pra casar com os pacotes, mesmo a imagem
sendo antiga e cheia de bugs conhecidos. Pra ter dado real e reprodutível, este lab usa uma
imagem **RHEL9/UBI** (ainda coberta pelo feed da Red Hat) — no caso, a mesma imagem do console
do `multicluster-engine` já em uso no seu hub ACM, escaneada ao vivo com **178 CVEs / 25
fixable**:

```bash
oc apply -f 10-WorkloadVulnerabilitiesConsole/ocp-manifests/01-namespace.yaml
oc apply -f 10-WorkloadVulnerabilitiesConsole/ocp-manifests/02-deployment.yaml
```

O `command: ["sleep", "infinity"]` é só pra não tentar rodar o binário do console do MCE de
verdade — a gente só precisa da imagem no nó pro Scanner analisar.

Confirme que subiu:

```bash
oc get pods -n lab-console-vulnerabilities
```

---

## Passo 3: Esperar o Sensor Escanear

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

---

## Passo 4: Explorar no Console do OpenShift

No menu lateral, **Security → Vulnerabilities**. Você vai ver a tela **Workload vulnerabilities**
(a mesma da captura no topo deste exercício), com **Project: All Projects** por padrão.

1. Troque o filtro de projeto pra `lab-console-vulnerabilities` (ou filtre por `Name` contendo o
   CVE que você quiser).
2. Repare nas colunas: **Images by severity** (quantas imagens são afetadas, por severidade —
   ícones de bandeira/seta), **Top CVSS**, **Top NVD CVSS**, **EPSS probability** (probabilidade
   de exploração ativa, dado do FIRST.org), **First discovered** (nesse cluster) e **Published**
   (data oficial do CVE).
3. Clique num CVE — por exemplo `CVE-2026-42338` (Important, CVSS 8.1, no pacote
   `nodejs-nodemon`/`npm`) — pra ver o painel de detalhe: descrição, versão corrigida
   (`Fixed in`), e quais imagens/deployments especificamente são afetados.
4. Alterne entre as abas **CVEs**, **Images** e **Deployments** no topo da tabela — a mesma
   navegação por perspectiva que existe na UI do Central, só que embutida no console do OCP.

O ponto central do exercício: um desenvolvedor com acesso só ao seu projeto no OpenShift agora
enxerga as CVEs do que ele mesmo faz deploy, **sem precisar de login separado no Central** nem
de uma role específica do RHACS — é RBAC do próprio OpenShift.

---

## Passo 5: Limpeza

```bash
oc delete namespace lab-console-vulnerabilities
```

Isso não desfaz o plugin habilitado nem o `SecuredCluster` — eles ficam pra outros labs de ACS
deste repositório. Se quiser reverter só o plugin, edite `spec.plugins` no `Console/cluster` e
remova `advanced-cluster-security` (não recomendado enquanto a automação em `acm-hub/` continuar
gerenciando essa policy — ela reaplicaria em segundos).

---

## Referências

- [Advanced Cluster Security for Kubernetes 4.11 Release Notes](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11/html/release_notes/index)
- [Viewing security information in the OpenShift web console — RHACS docs](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11)
- [Console \[operator.openshift.io/v1\] — Config APIs — OpenShift](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/config_apis/console-operator-openshift-io-v1)
