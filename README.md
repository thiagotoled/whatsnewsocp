# What's New in OpenShift & ACS — Laboratórios Práticos

Repositório com exercícios práticos sobre as novidades do **Red Hat OpenShift 4.20+** e do **Red Hat Advanced Cluster Security for Kubernetes (RHACS) 4.11**.
Cada diretório contém um laboratório independente com manifestos prontos para aplicar no cluster.

---

## Exercícios Disponíveis

| # | Exercício | Descrição |
|---|-----------|-----------|
| 1 | [In-place Pod Vertical Scaling](./InplacePodverticalscaling/README.md) | Ajuste de CPU e Memória de Pods em execução **sem reinicialização** |
| 2 | [External Secrets Operator](./ExternalSecretsOperator/README.md) | Sincronização bidirecional de segredos entre OpenShift e Azure Key Vault |
| 3 | [User Namespaces](./UserNamespaces/README.md) | Isolamento de UID/GID do container em relação ao host com `hostUsers: false` |
| 9 | [Encontrando Problemas Antes de Atualizar o Cluster](./UpgradeRecommendPrecheck/README.md) | Uso do `oc adm upgrade recommend` (GA no OCP 4.20) para identificar riscos (ex.: PodDisruptionBudget restritivo) antes de iniciar um update do OpenShift |
| 4 | [Managed Boot Images](./ManagedBootImages/README.md) | Atualização automática de imagens de boot nos MachineSets — provisionamento mais rápido |
| 5 | [Enhanced Vulnerability Management Reporting](./VulnerabilityManagementReporting/README.md) | Novas colunas (NVD CVSS, EPSS, Advisory, Component Version) nos relatórios de vulnerabilidade do RHACS 4.11 |
| 6 | [Policy Scope com Labels de Cluster/Namespace](./PolicyScopeLabels/README.md) | Restringir políticas do RHACS a clusters/namespaces específicos usando seletores de label |
| 7 | [Policy para oc debug / pods attach](./PolicyDebugPodAttach/README.md) | Detecção e enforcement de `pods/attach` (cobrindo `oc debug`, `oc attach`) no RHACS 4.11 |

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
whatsnewsocp/
├── InplacePodverticalscaling/
│   ├── README.md
│   └── ocp-manifests/
│       ├── 01-namespace.yaml
│       └── 02-deployment.yaml
├── ExternalSecretsOperator/
│   ├── README.md
│   └── ocp-manifests/
│       ├── 01-namespace.yaml
│       ├── 02-external-secrets-config.yaml
│       ├── 03-azure-credentials-secret.yaml
│       ├── 04-secret-store.yaml
│       ├── 05-external-secret.yaml
│       ├── 06-pod-check.yaml
│       ├── 07-push-source-secret.yaml
│       ├── 08-push-azure-credentials.yaml
│       ├── 09-push-secret-store.yaml
│       └── 10-push-secret.yaml
├── UserNamespaces/
│   ├── README.md
│   └── ocp-manifests/
│       ├── 01-namespace.yaml
│       ├── 02-deployment-no-userns.yaml
│       └── 03-deployment-with-userns.yaml
├── ManagedBootImages/
│   ├── README.md
│   └── ocp-manifests/
│       └── 01-machine-configuration.yaml
├── VulnerabilityManagementReporting/
│   ├── README.md
│   └── acs-manifests/
│       ├── 01-namespace.yaml
│       ├── 02-vulnerable-deployment.yaml
│       └── 03-report-on-demand.sh
├── PolicyScopeLabels/
│   ├── README.md
│   └── acs-manifests/
│       ├── 01-namespace-prod.yaml
│       ├── 02-namespace-dev.yaml
│       ├── 03-deployment-latest-tag.yaml
│       └── 04-policy-as-code-example.yaml
├── PolicyDebugPodAttach/
│   ├── README.md
│   └── acs-manifests/
│       ├── 01-namespace.yaml
│       └── 02-deployment.yaml
├── UpgradeRecommendPrecheck/
│   ├── README.md
│   └── ocp-manifests/
│       ├── 01-namespace.yaml
│       ├── 02-deployment.yaml
│       ├── 03-poddisruptionbudget-blocking.yaml
│       └── 04-poddisruptionbudget-fixed.yaml
└── acm-hub/
    ├── README.md
    └── policies/
        ├── kustomization.yaml
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
        ├── policy-gitops-operator-install.yaml
        ├── policy-webterminal-install.yaml
        ├── policy-oauth-configuration.yaml
        ├── policy-lab01.yaml
        ├── policy-lab02.yaml
        ├── policy-lab03.yaml
        ├── policy-lab05.yaml
        ├── policy-lab06.yaml
        ├── policy-lab07.yaml
        ├── policy-lab09.yaml
        └── policy-lab09-pdb-seed.yaml
```
