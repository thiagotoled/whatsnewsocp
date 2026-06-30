# Exercício 8: Scheduling de Compliance Operator Tailored Profiles — RHACS 4.11

A partir do RHACS 4.11, o **Compliance** do RHACS passou a rastrear **Tailored Profiles** e regras customizadas vindas do Compliance Operator: perfis customizados podem ser incluídos diretamente nas **scan configurations**, e os resultados aparecem na página **Coverage** e nos relatórios CSV do RHACS. Além disso, se o cluster OpenShift já tem o Compliance Operator instalado, dá para criar e gerenciar o **agendamento dos scans diretamente pela página Schedules do RHACS** — sem precisar criar manualmente o `ScanSettingBinding` no Compliance Operator, já que o RHACS faz isso por trás dos panos.

Neste laboratório você vai:

1. Instalar o Compliance Operator.
2. Criar um `TailoredProfile` customizando o perfil CIS.
3. Agendar o scan desse perfil customizado pela UI do RHACS (caminho recomendado no 4.11).
4. Validar que o RHACS criou o `ScanSettingBinding` automaticamente.
5. Ver uma alternativa 100% manual via `ScanSetting`/`ScanSettingBinding`, para quem não usa a página Schedules do RHACS.

---

## Pré-requisitos

- RHACS 4.11 (Central + Sensor) instalado e conectado ao cluster OpenShift, com a integração de **Compliance** habilitada para o cluster.
- `oc` autenticado com permissão de cluster-admin (necessário para instalar o Compliance Operator).

---

## Passo 1: Instalar o Compliance Operator

```bash
oc apply -f ComplianceTailoredProfilesScheduling/acs-manifests/01-namespace.yaml
oc apply -f ComplianceTailoredProfilesScheduling/acs-manifests/02-operatorgroup.yaml
oc apply -f ComplianceTailoredProfilesScheduling/acs-manifests/03-subscription.yaml
```

Aguarde o operador ficar pronto:

```bash
oc get csv -n openshift-compliance -w
```

Confirme que os perfis padrão (incluindo `ocp4-cis`) estão disponíveis:

```bash
oc get profiles.compliance.openshift.io -n openshift-compliance
```

---

## Passo 2: Criar o Tailored Profile

```bash
oc apply -f ComplianceTailoredProfilesScheduling/acs-manifests/04-tailored-profile.yaml
oc get tailoredprofile lab-cis-tailored -n openshift-compliance
```

Esse `TailoredProfile` estende o `ocp4-cis`, desabilita uma regra específica (com `rationale` documentando o motivo) e ajusta uma variável — exatamente o tipo de customização que o RHACS 4.11 agora rastreia nativamente.

---

## Passo 3: Agendar o scan pela página Schedules do RHACS

1. Na UI do RHACS, acesse **Compliance → Schedules → Create scan schedule**.
2. **Cluster:** selecione o cluster onde o Compliance Operator foi instalado.
3. **Profiles:** o `TailoredProfile` `lab-cis-tailored` deve aparecer na lista junto com os perfis padrão — essa é a novidade do 4.11 (antes, só perfis padrão apareciam aqui).
4. **Schedule:** configure, por exemplo, **Weekly, Monday, 06:00**.
5. **Name:** `lab-weekly-tailored-scan`.
6. Salve.

---

## Passo 4: Validar que o RHACS criou os recursos no Compliance Operator

```bash
oc get scansettingbindings -n openshift-compliance
oc get scansettings -n openshift-compliance
oc get compliancesuite -n openshift-compliance
```

Você deve ver um `ScanSettingBinding` referenciando o `TailoredProfile` `lab-cis-tailored`, criado automaticamente pelo RHACS — sem você precisar aplicar esse YAML manualmente.

Acompanhe o scan rodar:

```bash
oc get compliancescan -n openshift-compliance -w
```

Quando o status mudar para `DONE`, vá em **Compliance → Coverage** na UI do RHACS, filtre pelo perfil `lab-cis-tailored` e confirme que os resultados (PASS/FAIL/MANUAL) aparecem, incluindo a regra que você desabilitou (marcada como excluída pela customização). Você também pode exportar esses resultados em CSV pela mesma página.

---

## Passo 5 (alternativa): Agendamento manual via ScanSetting/ScanSettingBinding

Se preferir não usar a página Schedules do RHACS — por exemplo, em um fluxo GitOps onde tudo é `oc apply` — você pode criar o agendamento diretamente no Compliance Operator:

```bash
oc apply -f ComplianceTailoredProfilesScheduling/acs-manifests/05-scansetting.yaml
oc apply -f ComplianceTailoredProfilesScheduling/acs-manifests/06-scansettingbinding.yaml
```

Isso cria o mesmo tipo de agendamento (semanal, toda segunda às 06:00) apontando para o mesmo `TailoredProfile`, mas totalmente fora da UI do RHACS. O RHACS ainda assim vai detectar e exibir os resultados em **Compliance → Coverage**, graças ao rastreamento de Tailored Profiles do 4.11 — a diferença é só em quem é o dono do agendamento (Compliance Operator vs. RHACS).

> Não aplique o Passo 5 se você já criou o agendamento pela UI no Passo 3 — isso geraria dois `ScanSettingBinding` concorrentes para o mesmo perfil.

---

## Limpeza

```bash
oc delete scansettingbinding lab-cis-tailored-binding -n openshift-compliance --ignore-not-found
oc delete scansetting lab-weekly-scan-setting -n openshift-compliance --ignore-not-found
oc delete tailoredprofile lab-cis-tailored -n openshift-compliance
```

Remova também o agendamento `lab-weekly-tailored-scan` pela página **Compliance → Schedules** do RHACS, se ele tiver sido criado no Passo 3.

Para remover o Compliance Operator por completo:

```bash
oc delete subscription compliance-operator -n openshift-compliance
oc delete namespace openshift-compliance
```

---

## Referências

- [Managing compliance — RHACS 4.11](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11/html/operating/managing-compliance)
- [Using the Compliance Operator with RHACS](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/4.11/html/operating/compliance-operator-rhacs)
- [Compliance Operator — OpenShift Container Platform](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/security_and_compliance/compliance-operator)
