# Exercício 6: Policy Scope usando Labels de Cluster e Namespace — RHACS 4.11

Neste laboratório, você vai aprender a restringir onde uma política de segurança do RHACS é avaliada, usando o **Policy Scope** (Restrict by scope / Exclude by scope) com seletores de **cluster** e **namespace por label**, em vez de listar nomes fixos. Isso é essencial em ambientes multi-tenant, onde você quer que a mesma regra se aplique apenas a namespaces marcados como `environment=production`, por exemplo, sem precisar editar a política toda vez que um novo namespace de produção for criado.

---

## Pré-requisitos

- RHACS 4.11 (Central + Sensor) instalado e conectado ao cluster OpenShift.
- Acesso à UI do RHACS com permissão de gerenciar políticas (`WorkflowAdministration`).
- `oc` autenticado no cluster.

---

## Passo 1: Criar os namespaces de teste com labels diferentes

```bash
oc apply -f PolicyScopeLabels/acs-manifests/01-namespace-prod.yaml
oc apply -f PolicyScopeLabels/acs-manifests/02-namespace-dev.yaml
```

Confirme as labels aplicadas:

```bash
oc get ns lab-acs-scope-prod lab-acs-scope-dev --show-labels
```

---

## Passo 2: Implantar a mesma carga de trabalho "violadora" nos dois namespaces

O Deployment abaixo usa a tag `latest`, que viola a política padrão **Latest tag** do RHACS. Vamos aplicá-lo nos dois namespaces para depois comparar o comportamento:

```bash
oc apply -n lab-acs-scope-prod -f PolicyScopeLabels/acs-manifests/03-deployment-latest-tag.yaml
oc apply -n lab-acs-scope-dev  -f PolicyScopeLabels/acs-manifests/03-deployment-latest-tag.yaml
```

---

## Passo 3: Criar a política customizada com escopo por label

1. Na UI do RHACS, acesse **Platform Configuration → Policy Management → Create policy**.
2. **Policy details:**
   - **Name:** `Lab - Latest Tag (somente Production)`
   - **Severity:** Medium
   - **Categories:** Docker CIS
3. **Policy behavior:** Lifecycle Stage = `Deploy`, Response = `Inform` (sem enforcement, só para visualizarmos a violação).
4. **Policy criteria:** arraste o critério **Image Tag** e defina o valor `latest`.
5. **Policy scope** (passo principal deste lab): clique em **Restrict by scope** e adicione um escopo com:
   - **Cluster:** selecione o cluster onde os namespaces de teste foram criados.
   - **Namespace label:** `environment` = `production`
6. Salve e **habilite** a política.

---

## Passo 4: Validar que o escopo está sendo respeitado

1. Vá em **Violations** e filtre por `Lab - Latest Tag (somente Production)`.
2. Confirme que **apenas** o Deployment `app-latest-tag` do namespace `lab-acs-scope-prod` aparece como violação.
3. Confirme que o mesmo Deployment, rodando em `lab-acs-scope-dev`, **não gera violação** — mesmo a imagem e a tag sendo idênticas — porque o namespace não tem a label `environment=production`.

### Variante: Exclude by scope

Como exercício adicional, edite a política e, em vez de **Restrict by scope**, use **Exclude by scope** com `environment` = `development` numa política sem nenhuma restrição de cluster/namespace. O resultado prático deve ser o mesmo: violações aparecem em produção, mas não em desenvolvimento.

---

## Referência: Policy-as-Code (GitOps)

Para quem gerencia políticas via Git em vez da UI, o RHACS expõe o mesmo modelo de escopo através do schema `SecurityPolicy` (`config.stackrox.io/v1alpha1`), usado com `roxctl declarative-config` e a [configuração declarativa do Central](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11/html/configuring/declarative-configuration-using). Veja o exemplo comentado em:

```
PolicyScopeLabels/acs-manifests/04-policy-as-code-example.yaml
```

> **Importante:** esse arquivo não é aplicado com `oc apply` direto no cluster — ele é processado pelo `roxctl` para gerar o ConfigMap/Secret que o Central usa na configuração declarativa. O passo a passo principal deste lab (Passos 3 e 4) usa a UI, que é a forma mais direta de validar o comportamento de escopo.

---

## Limpeza

```bash
oc delete namespace lab-acs-scope-prod lab-acs-scope-dev
```

Remova também a política `Lab - Latest Tag (somente Production)` pela UI, se não for mais necessária.

---

## Referências

- [Managing security policies — RHACS 4.11](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11/html/operating/managing-security-policies)
- [Using declarative configuration — RHACS 4.11](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11/html/configuring/declarative-configuration-using)
