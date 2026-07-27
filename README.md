# What's New in OpenShift & ACS — Laboratórios Práticos

Repositório com exercícios práticos sobre as novidades do **Red Hat OpenShift 4.20+** e do **Red Hat Advanced Cluster Security for Kubernetes (RHACS) 4.11**.
Cada diretório contém um laboratório independente com manifestos prontos para aplicar no cluster.

---

## Exercícios Disponíveis

| # | Exercício | Descrição |
|---|-----------|-----------|
| 1 | [In-place Pod Vertical Scaling](./1-InplacePodverticalscaling/README.md) | Ajuste de CPU e Memória de Pods em execução **sem reinicialização** |
| 2 | [External Secrets Operator](./2-ExternalSecretsOperator/README.md) | Sincronização bidirecional de segredos entre OpenShift e Azure Key Vault |
| 3 | [User Namespaces](./3-UserNamespaces/README.md) | Isolamento de UID/GID do container em relação ao host com `hostUsers: false` |
| 4 | [Managed Boot Images](./4-ManagedBootImages/README.md) | Atualização automática de imagens de boot nos MachineSets — provisionamento mais rápido |
| 5 | [Enhanced Vulnerability Management Reporting](./5-VulnerabilityManagementReporting/README.md) **(candidato a remoção)** | Novas colunas (NVD CVSS, EPSS, Advisory, Component Version) nos relatórios de vulnerabilidade do RHACS 4.11 |
| 6 | [Policy Scope com Labels de Cluster/Namespace](./6-PolicyScopeLabels/README.md) **(candidato a remoção)** | Restringir políticas do RHACS a clusters/namespaces específicos usando seletores de label |
| 7 | [Policy para oc debug / pods attach](./7-PolicyDebugPodAttach/README.md) **(candidato a remoção)** | Detecção e enforcement de `pods/attach` (cobrindo `oc debug`, `oc attach`) no RHACS 4.11 |
| 8 | [Encontrando Problemas Antes de Atualizar o Cluster](./8-UpgradeRecommendPrecheck/README.md) | Uso do `oc adm upgrade recommend` (GA no OCP 4.20) para identificar riscos (ex.: PodDisruptionBudget restritivo) antes de iniciar um update do OpenShift |
| 9 | [Verificação de Assinatura de Imagens com Sigstore](./9-SigstoreImagePolicy/README.md) | Uso do `ImagePolicy` (GA no OCP 4.20) para exigir assinatura sigstore antes do pull — bloqueia com chave errada, libera com a chave real da Red Hat |

---

## Automação via ACM (em preparação)

O diretório [`acm-hub/`](./acm-hub/README.md) contém o esqueleto de Policies do RHACM (Advanced
Cluster Management) para pré-carregar o "boilerplate" de cada lab (namespace, deployment, operador)
nos clusters, deixando só a parte que É a lição para aplicação manual. Ainda depende de um hub ACM
que será criado — ver detalhes e cuidados (principalmente o do PDB do Lab 9) no README do diretório.

---

## Como usar

1. Clone o repositório:
```bash
git clone https://github.com/thiagotoled/whatsnewsocp.git
cd whatsnewsocp
```

2. Faça login no seu cluster OpenShift:
```bash
oc login --token=<TOKEN> --server=<API_URL>
```

3. Acesse o diretório do exercício desejado e siga o `README.md` correspondente.

---

## Estrutura do Repositório

```
.
├── 1-InplacePodverticalscaling
│   ├── README.md
│   └── ocp-manifests
│       ├── 01-namespace.yaml
│       └── 02-deployment.yaml
├── 2-ExternalSecretsOperator
│   ├── README.md
│   └── ocp-manifests
│       ├── 01-namespace.yaml
│       ├── 01-operator-config.yaml
│       ├── 02-external-secrets-config.yaml
│       ├── 03-azure-credentials-secret.yaml
│       ├── 04-secret-store.yaml
│       ├── 05-external-secret.yaml
│       ├── 06-pod-check.yaml
│       ├── 07-push-source-secret.yaml
│       ├── 08-push-azure-credentials.yaml
│       ├── 09-push-secret-store.yaml
│       └── 10-push-secret.yaml
├── 3-UserNamespaces
│   ├── README.md
│   └── ocp-manifests
│       ├── 01-namespace.yaml
│       ├── 02-deployment-no-userns.yaml
│       └── 03-deployment-with-userns.yaml
├── 4-ManagedBootImages
│   ├── README.md
│   └── ocp-manifests
│       └── 01-machine-configuration.yaml
├── 5-VulnerabilityManagementReporting
│   ├── README.md
│   └── acs-manifests
│       ├── 01-namespace.yaml
│       ├── 02-vulnerable-deployment.yaml
│       └── 03-report-on-demand.sh
├── 6-PolicyScopeLabels
│   ├── README.md
│   └── acs-manifests
│       ├── 01-namespace-prod.yaml
│       ├── 02-namespace-dev.yaml
│       ├── 03-deployment-latest-tag.yaml
│       └── 04-policy-as-code-example.yaml
├── 7-PolicyDebugPodAttach
│   ├── README.md
│   └── acs-manifests
│       ├── 01-namespace.yaml
│       └── 02-deployment.yaml
├── 8-UpgradeRecommendPrecheck
│   ├── README.md
│   └── ocp-manifests
│       ├── 01-namespace.yaml
│       ├── 02-deployment.yaml
│       ├── 03-poddisruptionbudget-blocking.yaml
│       └── 04-poddisruptionbudget-fixed.yaml
├── 9-SigstoreImagePolicy
│   ├── README.md
│   └── ocp-manifests
│       ├── 01-namespace.yaml
│       ├── 02-deployment.yaml
│       ├── 03-imagepolicy-wrong-key.yaml
│       └── 04-imagepolicy-redhat-key.yaml
├── README.md
└── acm-hub
    ├── README.md
    └── policies
        ├── 00-namespace.yaml
        ├── 01-managedclustersetbinding.yaml
        ├── 02-placement-local-cluster.yaml
        ├── 03-placementbinding-local-cluster.yaml
        ├── 04-placement-azure.yaml
        ├── 05-placement-vmware.yaml
        ├── 06-placement-all-lab-clusters.yaml
        ├── 07-placementbinding-all-lab-clusters.yaml
        ├── 08-placement-all.yaml
        ├── 09-placementbinding-all.yaml
        ├── 10-placementbinding-azure.yaml
        ├── kustomization.yaml
        ├── policy-gitops-operator-install.yaml
        ├── policy-webterminal-install.yaml
        ├── policy-oauth-configuration.yaml
        ├── policy-cluster-admin-rbac.yaml
        ├── policy-lab01.yaml
        ├── policy-lab02.yaml
        ├── policy-lab03.yaml
        ├── policy-lab08.yaml
        └── policy-lab09.yaml
```
