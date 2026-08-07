# Exercício 11: Instalar Helm Chart Direto de uma URL OCI/HTTPS no Console (4.22)

> **Navegação confirmada ao vivo**: o menu do Helm não fica em "Developer perspective → +Add"
> — fica em **Core platform (Administrator) → Ecosystem → Helm**, dentro de um projeto
> selecionado. O dropdown **Create** já mostra as três opções direto: **Helm Release**,
> **Repository** e **Helm chart URL** — essa última é a novidade deste lab (RFE-7114/7965).

Neste laboratório, você vai instalar um Helm chart no console do OpenShift **sem cadastrar um
repositório antes** — direto de uma URL `oci://` ou `https://` — a novidade do 4.22
(`Helm Console Enhancements`).

---

## Conceito Rápido

Até o 4.21, pra instalar um Helm chart pelo console (**Developer perspective → +Add → Helm
Chart**) você precisava primeiro que um `HelmChartRepository` (cluster-scoped) ou
`ProjectHelmChartRepository` (namespace-scoped) já estivesse cadastrado — um passo de admin
separado, antes de qualquer desenvolvedor conseguir instalar algo.

O 4.22 adiciona três coisas (RFE-7114 e RFE-7965):

- **Suporte a charts OCI**: navegar, inspecionar e instalar charts publicados como artefato OCI
  (`oci://`) direto dos repositórios já configurados.
- **Instalação direta por URL**: colar uma URL `oci://` ou `https://` na hora de instalar — sem
  precisar cadastrar repositório nenhum antes. Bom pra testar um chart uma vez só, ou pra um
  chart que só existe numa URL avulsa.
- **Autenticação no cadastro de repositório**: o formulário de adicionar um `HelmChartRepository`
  pelo console agora suporta `basicAuthConfig` direto na UI, sem precisar editar YAML pra
  repositórios privados.

---

## Pré-requisitos

- OpenShift 4.22.
- Acesso de developer/admin com permissão de criar recursos no seu namespace.

---

## Passo 1: Instalar Direto de uma URL OCI, Sem Cadastrar Nada

Selecione o projeto **`app`** (o mesmo namespace do Lab 2 — se você não rodou aquele lab,
crie primeiro: `oc new-project app`). No console: **Core platform → Ecosystem → Helm** → botão
**Create → Helm chart URL** → cole uma referência OCI pública, por exemplo:

```
oci://registry-1.docker.io/bitnamicharts/nginx
```

> **`Chart version` é obrigatório** (confirmado ao vivo, o formulário não deixa avançar sem
> isso) — use `25.0.18`.

Preencha o **Release name** (ex.: `nginx`) e instale. Nenhum `HelmChartRepository` foi criado —
o console foi direto na URL, resolveu o chart, e mostrou pra você inspecionar antes de instalar.
Não existe nenhum objeto Kubernetes de "repositório" — só o `HelmRelease`/Secret que o Helm
sempre cria pra rastrear a instalação em si.

```bash
oc get secret -l owner=helm -n app
```

---

## Passo 2: Limpeza

```bash
helm uninstall nginx -n app
```

---

## Referências

- [Working with Helm charts — OpenShift Container Platform docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.11/html/building_applications/working-with-helm-charts)
- [Advanced Helm support in the OpenShift web console — Red Hat Developer](https://developers.redhat.com/blog/2020/07/20/advanced-helm-support-in-the-openshift-4-5-web-console)
