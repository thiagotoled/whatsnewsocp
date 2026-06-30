# Exercício 7: Policy para `oc debug` / `pods/attach` — RHACS 4.11

O RHACS detecta e pode aplicar enforcement sobre eventos de Kubernetes vindos do audit log do cluster, como `pods/exec` e `pods/portforward`. Na série 4.x (ROX-24311) essa cobertura foi estendida para o evento **`pods/attach`**, o que é importante porque vários comandos do dia a dia do `oc`/`kubectl` usam esse verbo por baixo dos panos:

- `oc attach` / `kubectl attach` → usa `pods/attach` diretamente.
- `oc debug <pod/deployment>` → cria um pod (ou container efêmero) e em seguida faz **attach** a ele.
- `oc rsh` → usa `pods/exec`.

Sem cobertura de `pods/attach`, alguém poderia contornar uma política de "bloquear exec em produção" simplesmente usando `oc debug` ou `oc attach` em vez de `oc exec`/`oc rsh`. Neste laboratório você vai criar uma política que cobre os três verbos e validar a detecção.

---

## Pré-requisitos

- RHACS 4.11 (Central + Sensor) instalado e conectado ao cluster OpenShift.
- Acesso à UI do RHACS com permissão de gerenciar políticas.
- O cluster precisa ter a integração com o **audit log do Kubernetes** habilitada para o Sensor (padrão em clusters OpenShift gerenciados pelo RHACS Operator) e, se for usar enforcement, o **Admission Controller** habilitado.
- `oc` autenticado no cluster com permissão para `pods/exec`, `pods/attach` e `pods/portforward` no namespace de teste.

---

## Passo 1: Implantar a carga de trabalho alvo

```bash
oc apply -f PolicyDebugPodAttach/acs-manifests/01-namespace.yaml
oc apply -f PolicyDebugPodAttach/acs-manifests/02-deployment.yaml
oc get pods -n lab-acs-debug-attach -w
```

---

## Passo 2: Revisar a política padrão e criar a variante customizada

1. Acesse **Platform Configuration → Policy Management** e procure a política padrão **`Kubernetes Actions: Exec into Pod`**. Abra-a para ver como o critério é montado (Event Source = Kubernetes Event, campo **Kubernetes Resource**).
2. Clone essa política (**Actions → Clone policy**) com o nome `Lab - Exec, Attach e Port-Forward em Pods`.
3. Na política clonada, em **Policy criteria**, garanta que o critério **Kubernetes Resource** inclua os três valores:
   - `Pods Exec`
   - `Pods Attach`
   - `Pods Portforward`
4. (Opcional) Em **Policy scope**, restrinja ao namespace `lab-acs-debug-attach` para não gerar ruído com outras cargas do cluster durante o teste.
5. Defina **Response**: comece com `Inform` (apenas alerta). Depois de validar a detecção, você pode mudar para `Inform and Enforce` para bloquear via Admission Controller.
6. Salve e habilite a política.

> Se for usar enforcement, confirme em **Platform Configuration → Clusters → <seu cluster> → Static Configuration** que o toggle **"Enable Admission Controller Webhook to listen on exec and port-forward events"** está ligado — sem ele, o Admission Controller não intercepta esses verbos.

---

## Passo 3: Reproduzir os eventos e gerar violações

Em três terminais (ou sequencialmente), gere os três tipos de evento contra o pod do `target-app`:

```bash
POD=$(oc get pod -n lab-acs-debug-attach -l app=target-app -o jsonpath='{.items[0].metadata.name}')

# 1) pods/exec
oc rsh -n lab-acs-debug-attach "$POD"

# 2) pods/attach (oc debug cria um pod efêmero e faz attach nele)
oc debug -n lab-acs-debug-attach "pod/$POD"

# 3) pods/portforward
oc port-forward -n lab-acs-debug-attach "$POD" 8080:80
```

---

## Passo 4: Validar na UI do RHACS

1. Vá em **Violations** e filtre por `Lab - Exec, Attach e Port-Forward em Pods`.
2. Confirme que aparecem violações distintas para cada verbo (`exec`, `attach`, `portforward`), cada uma com o **usuário do Kubernetes** que executou a ação, o pod alvo e o timestamp — essa informação vem diretamente do audit log do cluster.

---

## Passo 5 (opcional): Testar o enforcement e o break-glass

1. Mude a política para `Inform and Enforce` e tente rodar `oc debug` novamente — o Admission Controller deve bloquear a requisição.
2. Para um acesso emergencial legítimo, adicione a anotação de break-glass ao recurso antes da ação (ex.: no Deployment ou via `oc patch`):

```bash
oc annotate pod -n lab-acs-debug-attach "$POD" admission.stackrox.io/break-glass="INC-1234" --overwrite
```

3. Repita o `oc debug` — a ação deve ser permitida, mas o RHACS ainda registra uma violação destacando que houve um bypass do Admission Controller, incluindo a anotação usada como justificativa.

---

## Limpeza

```bash
oc delete namespace lab-acs-debug-attach
```

Remova também a política `Lab - Exec, Attach e Port-Forward em Pods` pela UI, se não for mais necessária.

---

## Referências

- [Using admission controller enforcement — RHACS 4.11](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11/html/operating/use-admission-controller-enforcement)
- [Managing security policies — RHACS 4.11](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11/html/operating/managing-security-policies)
