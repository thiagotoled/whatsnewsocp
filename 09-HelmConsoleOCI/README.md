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

No console: **Core platform → Ecosystem → Helm** (dentro do projeto desejado) → botão
**Create → Helm chart URL** → cole uma referência OCI pública, por exemplo:

```
oci://registry-1.docker.io/bitnamicharts/nginx
```

Preencha o **Release Name** e instale. Nenhum `HelmChartRepository` foi criado — o console foi
direto na URL, resolveu o chart, e mostrou pra você inspecionar antes de instalar. Não existe
nenhum objeto Kubernetes de "repositório" — só o `HelmRelease`/Secret que o Helm sempre cria pra
rastrear a instalação em si.

```bash
oc get secret -l owner=helm -n <seu-namespace>
```

---

## Passo 2: Mesma Coisa, com uma URL HTTPS Direta

Repita o Passo 1, mas usando uma URL `https://` apontando direto pro `.tgz` de um chart
empacotado (em vez de uma referência OCI) — o mesmo fluxo de "colar URL, sem repositório"
funciona pros dois protocolos.

> Nota: não incluí uma URL HTTPS específica pronta pro `.tgz` porque não confirmei ao vivo uma
> que seja estável a longo prazo — ao preparar a aula, valide qual chart público em `.tgz` você
> vai usar (ex.: algum publicado nas releases de um repositório GitHub) antes de depender dele
> na frente da turma.

---

## Passo 3: Repositório Privado com Autenticação (Conceitual)

Se você tiver um repositório Helm privado disponível: **Core platform → Ecosystem → Helm →
Repositories → Create → Repository**, e no formulário (não no YAML) preencha usuário e senha —
o console agora grava isso como `basicAuthConfig` no `Secret` referenciado pelo
`HelmChartRepository`, sem você precisar montar o `Secret` manualmente primeiro.

---

## Passo 4: Limpeza

```bash
helm uninstall <release-name> -n <seu-namespace>
```

---

## Referências

- [Working with Helm charts — OpenShift Container Platform docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.11/html/building_applications/working-with-helm-charts)
- [Advanced Helm support in the OpenShift web console — Red Hat Developer](https://developers.redhat.com/blog/2020/07/20/advanced-helm-support-in-the-openshift-4-5-web-console)
