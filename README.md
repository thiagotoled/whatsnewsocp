# What's New in OpenShift & ACS: Laboratórios Práticos

Repositório com exercícios práticos sobre as novidades do **Red Hat OpenShift 4.20+**, do **Red Hat Advanced Cluster Security for Kubernetes (RHACS) 4.11**, e do **Red Hat Advanced Cluster Management (ACM) 2.17**.
Cada diretório contém um laboratório independente com manifestos prontos para aplicar no cluster.

---

## Exercícios Disponíveis

| # | Exercício | Descrição | OCP | Maturidade | Tempo |
|---|-----------|-----------|------|------------|-------|
| 1 | [In-place Pod Vertical Scaling](./1-InplacePodverticalscaling/README.md) | Ajuste de CPU e Memória de Pods em execução **sem reinicialização** | 4.20+ | GA (4.22) | ~15 min |
| 2 | [External Secrets Operator](./2-ExternalSecretsOperator/README.md) | Sincronização bidirecional de segredos entre OpenShift e Azure Key Vault | 4.20+ | GA | ~25 min |
| 3 | [User Namespaces](./3-UserNamespaces/README.md) | Isolamento de UID/GID do container em relação ao host com `hostUsers: false` | 4.20+ | GA | ~10 min |
| 4 | [Managed Boot Images](./4-ManagedBootImages/README.md) | Atualização automática de imagens de boot nos MachineSets, provisionamento mais rápido | 4.21+ | GA | ~20 min |
| 5 | [Encontrando Problemas Antes de Atualizar o Cluster](./5-UpgradeRecommendPrecheck/README.md) | Uso do `oc adm upgrade recommend` para identificar riscos antes de iniciar um update | 4.20+ | GA | ~30 min |
| 6 | [Verificação de Assinatura de Imagens com Sigstore](./6-SigstoreImagePolicy/README.md) | Uso do `ImagePolicy` para exigir assinatura sigstore antes do pull | 4.20+ | GA | ~20 min |
| 7 | [Vulnerabilidades no Console e Mais Controle no CRS](./7-VulnerabilitiesAndCRS/README.md) | Plugin `advanced-cluster-security` do RHACS no console do OpenShift + controles de **validade** e **max registrations** na geração do CRS (RHACS 4.11) | 4.20+ / ACS 4.11 | GA | ~25 min |
| 8 | [GitOps Argo Agent Addon](./8-GitOpsArgoAgent/README.md) **(não validado ao vivo)** | Modelo **pull** de GitOps multicluster do ACM 2.17 — managed cluster conecta no hub, não o contrário | ACM 2.17 | Tech Preview | ~35 min |
| 9 | [Dashboards com o Red Hat Build of Perses](./9-GrafanaToPerses/README.md) **(não validado ao vivo)** | Dois caminhos: Parte 1 — COO genérico (`UIPlugin`/`PersesDashboard`, GA), isolado no cluster de cada aluno. Parte 2 — Multicluster Observability Add-on nativo do ACM (Technology Preview), dashboards de frota prontos, pré-configurado no hub | COO 1.5 / ACM 2.17 | GA + Tech Preview | ~30 min |
| 10 | [OLM v1 — `ClusterExtension`](./10-OLMv1ClusterExtension/README.md) **(não validado ao vivo)** | `ServiceAccount`+RBAC explícito em vez de permissões automáticas, upgrade só editando `spec.source.catalog.version` | 4.18+ | GA | ~20 min |
| 11 | [Helm Chart Direto de URL OCI/HTTPS no Console](./11-HelmConsoleOCI/README.md) **(não validado ao vivo)** | Instala um Helm chart sem cadastrar repositório antes — cola a URL `oci://` ou `https://` na hora | 4.22 | GA | ~15 min |

> **OCP 4.22** (lançado em 23 de junho de 2026, baseado no Kubernetes 1.35 "Timbernetes"):
> o In-place Pod Vertical Scaling (Lab 1) passou de Tech Preview para **GA**. Labs 8-11 cobrem
> outras novidades do 4.20-4.22 e do ACM 2.17/RHACS 4.11 (GitOps pull model, Perses, OLM v1,
> Helm Console) — marcados **"não validado ao vivo"** até serem testados num cluster real.

---

## Automação via ACM

O diretório [`acm-hub/`](./acm-hub/README.md) contém as Policies do RHACM (Advanced Cluster
Management) que rodam de verdade no hub e pré-carregam o "boilerplate" de cada lab (namespace,
deployment, operador) em todo cluster importado, deixando só a parte que É a lição para
aplicação manual. Ver a tabela completa, os cuidados (PDB do Lab 5, secrets que não estão no
git, Redirect URI do Entra ID) e o passo a passo pra importar um cluster novo no README do
diretório.

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
├── 5-UpgradeRecommendPrecheck
│   ├── README.md
│   └── ocp-manifests
│       ├── 01-namespace.yaml
│       ├── 02-deployment.yaml
│       ├── 03-poddisruptionbudget-blocking.yaml
│       └── 04-poddisruptionbudget-fixed.yaml
├── 6-SigstoreImagePolicy
│   ├── README.md
│   └── ocp-manifests
│       ├── 01-namespace.yaml
│       ├── 02-deployment.yaml
│       ├── 03-imagepolicy-wrong-key.yaml
│       └── 04-imagepolicy-redhat-key.yaml
├── 7-VulnerabilitiesAndCRS
│   ├── README.md
│   └── ocp-manifests
│       ├── 01-namespace.yaml
│       └── 02-deployment.yaml
├── 8-GitOpsArgoAgent
│   ├── README.md
│   └── manifests
│       ├── 01-appset-push-model.yaml
│       ├── 02-application-pull-model.yaml
│       ├── 03-argocd-agent-mode.yaml
│       ├── 04-appproject-wildcard.yaml
│       ├── 05-managedclustersetbinding.yaml
│       ├── 06-gitopscluster-agent.yaml
│       ├── 07-agent-view-clusterrolebinding.yaml
│       └── app
│           └── deployment.yaml
├── 9-GrafanaToPerses
│   ├── README.md
│   └── manifests
│       ├── 01-uiplugin-monitoring.yaml
│       ├── 02-perses-global-datasource.yaml
│       ├── 03-namespace.yaml
│       ├── 04-demo-deployment.yaml
│       └── 05-persesdashboard.yaml
├── 10-OLMv1ClusterExtension
│   ├── README.md
│   └── manifests
│       ├── 01-namespace.yaml
│       ├── 02-serviceaccount-rbac.yaml
│       └── 03-clusterextension.yaml
├── 11-HelmConsoleOCI
│   ├── README.md
│   └── manifests
│       └── 01-helmchartrepository.yaml
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
        ├── policy-acs-operator-install.yaml
        ├── policy-acs-central.yaml
        ├── policy-acs-secured-cluster.yaml
        ├── policy-lab01.yaml
        ├── policy-lab02.yaml
        ├── policy-lab03.yaml
        ├── policy-lab05.yaml
        ├── policy-lab06.yaml
        └── policy-lab07.yaml
```
