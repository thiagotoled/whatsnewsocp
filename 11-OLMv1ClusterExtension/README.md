# Exercício 11: OLM v1 — Instalando um Operator via `ClusterExtension`

> **Ainda não validado ao vivo** — escrito com base na documentação oficial e no código-fonte
> real do `operator-framework/operator-controller` (conferido diretamente no GitHub, já que a
> documentação encontrada sobre "Helm via ClusterExtension" se mostrou desatualizada/incorreta
> — ver aviso no Passo 3). Pendente de teste num cluster 4.20+ real.

Neste laboratório, você vai instalar o **mesmo operator que este repositório já usa em outro
lugar** (`rhacs-operator`, o operator do RHACS — ver `acm-hub/policies/policy-acs-operator-install.yaml`)
de um jeito diferente: via **OLM v1** (`ClusterExtension`), o sucessor GA (desde o OCP 4.18) do
OLM clássico baseado em `Subscription`/`CatalogSource`.

---

## Conceito Rápido

O OLM clássico (o que `policy-acs-operator-install.yaml` deste repositório usa, via
`OperatorPolicy`/`Subscription`) concede **permissões automaticamente** — quando você assina um
operator, o OLM cria as `Role`/`RoleBinding` necessárias sozinho, sem você precisar declarar
nada. Conveniente, mas opaco: difícil saber de antemão exatamente o que um operator vai poder
fazer no cluster.

O **OLM v1** inverte isso — modelo de **privilégio mínimo explícito**:

| | OLM clássico (`Subscription`) | OLM v1 (`ClusterExtension`) |
|---|---|---|
| Permissões | O OLM concede automaticamente | Você declara um `ServiceAccount` com o RBAC necessário, **antes** de instalar |
| Objeto principal | `Subscription` + `CatalogSource` + `InstallPlan` (vários objetos) | `ClusterExtension` (um objeto só, direto) |
| Upgrade | Aprovação via `InstallPlan` (Automatic/Manual) | Editar `spec.source.catalog.version` no próprio `ClusterExtension` |
| Se faltar permissão | Instala, pode falhar silenciosamente depois | Falha a validação **antes** de instalar/atualizar |

---

## Pré-requisitos

- OpenShift 4.18+ (OLM v1 é GA desde então; usamos 4.20+ neste repositório).
- Acesso de administrador ao cluster.
- O catálogo padrão `openshift-redhat-operators` já vem instalado como `ClusterCatalog` — não
  precisa criar nenhum catálogo pra este lab.

---

## Passo 1: Ver o Catálogo e o Pacote Disponível

```bash
oc get clustercatalog
oc get clustercatalog openshift-redhat-operators -o yaml
```

Confirme que o `rhacs-operator` está disponível no catálogo (a API de busca de pacotes do OLM
v1 é via `oc get package` num futuro CLI plugin, ou consultando o `ClusterCatalog` via `grpcurl`
— o jeito mais simples pra este lab é conferir direto na UI: **OperatorHub → busque
"Advanced Cluster Security"**, que já usa OLM v1 por baixo dos panos desde a 4.18 mesmo quando
instalado pela UI).

---

## Passo 2: `ServiceAccount` + RBAC (o Passo que o OLM Clássico Não Tinha)

Diferente do `Subscription`, você precisa declarar quem tem permissão pra instalar o operator
**antes** de criar o `ClusterExtension`:

```bash
oc apply -f 11-OLMv1ClusterExtension/manifests/01-namespace.yaml
oc apply -f 11-OLMv1ClusterExtension/manifests/02-serviceaccount-rbac.yaml
```

> **Isto é `cluster-admin`, só pra fins didáticos.** Em produção, o certo é derivar a permissão
> mínima real que o `rhacs-operator` precisa (o próprio operator geralmente documenta o
> `ClusterRole` necessário) — não usar `cluster-admin` num `ClusterExtension` de verdade.

---

## Passo 3: Criar o `ClusterExtension`

```bash
oc apply -f 11-OLMv1ClusterExtension/manifests/03-clusterextension.yaml
oc get clusterextension rhacs-operator-v1 -o yaml
```

Espere a condição `Installed: True, reason: Succeeded` e `Progressing: True, reason: Succeeded`
(o `reason: Succeeded` no `Progressing` significa "terminou de progredir com sucesso", não "está
progredindo").

> **Sobre "Helm via ClusterExtension"**: no material de pesquisa pra este lab, várias fontes
> sugeriam que `ClusterExtension` teria um `sourceType: Helm` pra instalar charts Helm
> diretamente, sem precisar do formato de bundle OLM. Conferindo o código-fonte real do
> `operator-controller` (`api/v1/clusterextension_types.go`, branch `main`), `spec.source.sourceType`
> só aceita `"Catalog"` — **não existe** um sourceType Helm direto. Ou essa info estava
> desatualizada, ou é uma feature ainda não lançada. Vale confirmar num cluster 4.22 real antes
> de prometer isso numa aula.

---

## Passo 4: Comparar com o Jeito que Este Repositório Já Instala o Mesmo Operator

Este repositório já tem `rhacs-operator` instalado via OLM clássico, em
[`acm-hub/policies/policy-acs-operator-install.yaml`](../acm-hub/policies/policy-acs-operator-install.yaml)
— um `OperatorPolicy` (que por baixo é `Subscription`/`CatalogSource`). Compare os dois
objetos-fonte lado a lado:

```bash
oc get subscription -A | grep rhacs
oc get clusterextension rhacs-operator-v1
```

Mesmo operator, dois modelos de instalação coexistindo no mesmo cluster — dá pra rodar os dois
ao mesmo tempo (em namespaces diferentes) sem conflito, já que o OLM v1 não usa mais
`OperatorGroup` do jeito antigo.

---

## Passo 5: Upgrade — Só Editar a Versão

```bash
oc patch clusterextension rhacs-operator-v1 --type merge \
  -p '{"spec":{"source":{"catalog":{"version":"<versão-mais-nova-disponível>"}}}}'
oc get clusterextension rhacs-operator-v1 -w
```

Sem `InstallPlan` pra aprovar manualmente — se o `ServiceAccount` do Passo 2 não tiver
permissão suficiente pra versão nova, o `ClusterExtension` fica em `Progressing: False` com o
motivo exato no `status.conditions`, **antes** de qualquer coisa quebrar de verdade.

---

## Passo 6: Limpeza

```bash
oc delete -f 11-OLMv1ClusterExtension/manifests/03-clusterextension.yaml
oc delete -f 11-OLMv1ClusterExtension/manifests/02-serviceaccount-rbac.yaml
oc delete -f 11-OLMv1ClusterExtension/manifests/01-namespace.yaml
```

---

## Referências

- [Manage operators as ClusterExtensions with OLM v1 — Red Hat Developer](https://developers.redhat.com/articles/2025/06/02/manage-operators-clusterextensions-olm-v1)
- [`operator-framework/operator-controller` — código-fonte da API `ClusterExtension`](https://github.com/operator-framework/operator-controller/blob/main/api/v1/clusterextension_types.go)
- [Announcing OLM v1 — Red Hat](https://www.redhat.com/en/blog/announcing-olm-v1-next-generation-operator-lifecycle-management)
- [Extensions — OpenShift Container Platform 4.21 docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html-single/extensions/index)
