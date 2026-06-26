# Exercício 4: Managed Boot Images no OpenShift 4.21+

Neste laboratório, você vai habilitar o gerenciamento automático de **Boot Images** via `MachineConfiguration`. Quando ativado, o Machine Config Operator (MCO) mantém a imagem de boot nos MachineSets sempre atualizada para a versão correta do RHCOS do cluster — eliminando a necessidade de atualização on-the-fly durante o provisionamento de novos nós.

---

## Conceito Rápido

Quando um novo nó é provisionado, a máquina precisa inicializar com a imagem de disco correta (RHCOS). Sem o gerenciamento de Boot Images:

1. O nó sobe com uma imagem desatualizada
2. Durante o boot, o MCO precisa aplicar atualizações de OS — processo demorado
3. Resultado: provisionamento mais lento (~12 minutos em testes com OCP 4.21)

Com o Managed Boot Images habilitado:

1. O MCO atualiza o campo `image` dos MachineSets automaticamente após cada upgrade do cluster
2. O novo nó já sobe com a imagem correta
3. Resultado: provisionamento mais rápido (~8 minutos nos mesmos testes)

---

## Pré-requisitos

- OpenShift 4.10+ (GA para MAPI MachineSets)
- Acesso de administrador ao cluster
- CLI `oc` autenticado

---

## Passo 1: Verificar o Estado Atual

Verifique se o recurso `MachineConfiguration` já existe no cluster e se o `managedBootImages` está configurado:

```bash
oc get machineconfiguration cluster -o yaml
```

Se o campo `managedBootImages` estiver ausente ou vazio, o gerenciamento está desativado — o MCO **não** atualiza as imagens dos MachineSets automaticamente.

Veja também qual imagem está configurada atualmente nos MachineSets:

```bash
oc get machineset -n openshift-machine-api -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.providerSpec.value.image}{"\n"}{end}'
```

---

## Passo 2: Habilitar o Managed Boot Images

Aplique o manifesto que habilita o gerenciamento automático para todos os MachineSets MAPI:

```bash
oc apply -f ManagedBootImages/ocp-manifests/01-machine-configuration.yaml
```

O campo `selection.mode: All` instrui o MCO a gerenciar **todos** os MachineSets do grupo `machine.openshift.io`.

---

## Passo 3: Validar a Reconciliação

Aguarde o MCO reconciliar e verifique o status:

```bash
oc get machineconfiguration cluster -o jsonpath='{.status.conditions}' | jq .
```

A saída esperada mostra o progresso e conclusão da atualização:

```json
[
  {
    "type": "BootImageUpdateProgressing",
    "status": "False",
    "reason": "MAPIMachineSetUpdated",
    "message": "Reconciled 3 of 3 MAPI MachineSets | Reconciled 0 of 0 ControlPlaneMachineSets ..."
  },
  {
    "type": "BootImageUpdateDegraded",
    "status": "False",
    "reason": "MAPIMachineSetUpdated",
    "message": "0 Degraded MAPI MachineSets ..."
  }
]
```

---

## Passo 4: Confirmar Atualização da Imagem nos MachineSets

Após a reconciliação, verifique que o campo `image` dos MachineSets foi atualizado pelo MCO para a versão correta do RHCOS:

```bash
oc get machineset -n openshift-machine-api -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.providerSpec.value.image}{"\n"}{end}'
```

Em clusters Azure/ARO, o campo `image` deve refletir a versão atualizada. Exemplo de antes e depois no Azure:

**Antes:**
```yaml
image:
  offer: aro4
  publisher: azureopenshift
  sku: aro_416
  version: 9.4.20240219
  type: MarketplaceNoPlan
```

**Depois:**
```yaml
image:
  offer: aro4
  publisher: azureopenshift
  sku: aro_420
  version: 9.6.20251015
  type: MarketplaceNoPlan
```

---

## Passo 5: Medir o Impacto no Provisionamento

Escale um MachineSet para provisionar um novo nó e meça o tempo:

```bash
MACHINESET=$(oc get machineset -n openshift-machine-api -o name | head -1)

# Registre o horário de início
date

# Escale para +1 réplica
oc scale $MACHINESET -n openshift-machine-api --replicas=<replicas_atuais+1>

# Acompanhe o provisionamento
oc get machine -n openshift-machine-api -w
```

Aguarde o novo `Machine` atingir o status `Running` e confirme o nó pronto:

```bash
oc get nodes -w
```

> **Resultado esperado:** O novo nó deve ficar pronto em ~8 minutos, contra ~12 minutos sem o Managed Boot Images habilitado.

---

## Passo 6: Desabilitar (Opcional)

Para desabilitar o gerenciamento automático e retornar ao comportamento padrão:

```bash
oc patch machineconfiguration cluster --type=merge -p '{"spec":{"managedBootImages":{"machineManagers":[]}}}'
```

---

## Referências

- [Documentação oficial: Managed Boot Images no OCP 4.21](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html-single/machine_configuration/index#mco-update-boot-images)
