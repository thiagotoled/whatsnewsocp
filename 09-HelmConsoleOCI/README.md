# Exercício 11: Instalar Helm Chart Direto de uma URL OCI/HTTPS no Console (4.22)

> **Parcialmente validado ao vivo em OCP 4.22.8**: confirmei os pedaços que dão pra testar via
> CLI — o CRD `helmchartrepositories.helm.openshift.io` existe, o `HelmChartRepository` do
> Passo 1 aplica limpo, a URL `https://redhat-developer.github.io/redhat-helm-charts/index.yaml`
> responde `200`, e a referência OCI usada no Passo 2
> (`oci://registry-1.docker.io/bitnamicharts/nginx`) resolve de verdade (`helm show chart`
> puxou o chart normalmente). **O que eu não consegui confirmar**: os Passos 2-4 são só UI do
> console (Developer perspective → +Add → Helm Chart) — não tenho como abrir navegador aqui pra
> clicar e confirmar que a opção "instalar por URL" (RFE-7114/7965) realmente aparece nesse
> build específico do console. Abra o console manualmente antes da aula pra confirmar essa
> parte.

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

## Passo 1: O Jeito Clássico (Comparação) — Repositório Cadastrado Antes

Cadastre um repositório Helm público conhecido:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/09-HelmConsoleOCI/manifests/01-helmchartrepository.yaml
```

No console: **Developer perspective → +Add → Helm Chart** — o catálogo mostra os charts desse
repositório. É o fluxo que já existe desde o 4.8: alguém (admin) precisa ter cadastrado o
repositório **antes** de qualquer chart aparecer ali.

---

## Passo 2: A Novidade — Instalar Direto de uma URL OCI, Sem Cadastrar Nada

No console: **Developer perspective → +Add → Helm Chart** → procure a opção de instalar **por
URL** (em vez de escolher um chart já listado do catálogo) → cole uma referência OCI pública,
por exemplo:

```
oci://registry-1.docker.io/bitnamicharts/nginx
```

Preencha o **Release Name** e instale. Nenhum `HelmChartRepository` foi criado — o console foi
direto na URL, resolveu o chart, e mostrou pra você inspecionar antes de instalar.

Compare com o Passo 1: aqui não existe nenhum objeto Kubernetes de "repositório" — só o
`HelmRelease`/Secret que o Helm sempre cria pra rastrear a instalação em si.

```bash
oc get secret -l owner=helm -n <seu-namespace>
```

---

## Passo 3: Mesma Coisa, com uma URL HTTPS Direta

Repita o Passo 2, mas usando uma URL `https://` apontando direto pro `.tgz` de um chart
empacotado (em vez de uma referência OCI) — o mesmo fluxo de "colar URL, sem repositório"
funciona pros dois protocolos.

> Nota: não incluí uma URL HTTPS específica pronta pro `.tgz` porque não confirmei ao vivo uma
> que seja estável a longo prazo — ao preparar a aula, valide qual chart público em `.tgz` você
> vai usar (ex.: algum publicado nas releases de um repositório GitHub) antes de depender dele
> na frente da turma.

---

## Passo 4: Repositório Privado com Autenticação (Conceitual)

Se você tiver um repositório Helm privado disponível: **Developer perspective → +Add → Helm
Chart Repositories → Create HelmChartRepository**, e no formulário (não no YAML) preencha usuário
e senha — o console agora grava isso como `basicAuthConfig` no `Secret` referenciado pelo
`HelmChartRepository`, sem você precisar montar o `Secret` manualmente primeiro.

---

## Passo 5: Limpeza

```bash
helm uninstall <release-name> -n <seu-namespace>
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/09-HelmConsoleOCI/manifests/01-helmchartrepository.yaml
```

---

## Referências

- [Working with Helm charts — OpenShift Container Platform docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.11/html/building_applications/working-with-helm-charts)
- [Advanced Helm support in the OpenShift web console — Red Hat Developer](https://developers.redhat.com/blog/2020/07/20/advanced-helm-support-in-the-openshift-4-5-web-console)
