# What's New in OpenShift & ACS: Laboratórios Práticos

Repositório com exercícios práticos sobre as novidades do **Red Hat OpenShift 4.20+**, do **Red Hat Advanced Cluster Security for Kubernetes (RHACS) 4.11**, e do **Red Hat Advanced Cluster Management (ACM) 2.17**.
Cada diretório contém um laboratório independente com manifestos prontos para aplicar no cluster.

---

## Exercícios Disponíveis

| # | Exercício | Descrição | OCP | Maturidade | Tempo |
|---|-----------|-----------|------|------------|-------|
| 1 | [In-place Pod Vertical Scaling](./01-InplacePodverticalscaling/README.md) | Ajuste de CPU e Memória de Pods em execução **sem reinicialização** | 4.20+ | GA (4.22) | ~15 min |
| 2 | [External Secrets Operator](./02-ExternalSecretsOperator/README.md) | Sincronização bidirecional de segredos entre OpenShift e Azure Key Vault | 4.20+ | GA | ~25 min |
| 3 | [User Namespaces](./03-UserNamespaces/README.md) | Isolamento de UID/GID do container em relação ao host com `hostUsers: false` | 4.20+ | GA | ~10 min |
| 4 | [Managed Boot Images](./04-ManagedBootImages/README.md) | Atualização automática de imagens de boot nos MachineSets, provisionamento mais rápido | 4.21+ | GA | ~20 min |
| 5 | [Verificação de Assinatura de Imagens com Sigstore](./05-SigstoreImagePolicy/README.md) | Uso do `ImagePolicy` para exigir assinatura sigstore antes do pull | 4.20+ | GA | ~20 min |
| 6 | [Vulnerabilidades no Console e Mais Controle no CRS](./06-VulnerabilitiesAndCRS/README.md) | Plugin `advanced-cluster-security` do RHACS no console do OpenShift + controles de **validade** e **max registrations** na geração do CRS (RHACS 4.11) | 4.20+ / ACS 4.11 | GA | ~25 min |
| 7 | [GitOps Argo Agent Addon](./07-GitOpsArgoAgent/README.md) **(exige managed cluster real)** | Modelo **pull** de GitOps multicluster do ACM 2.17 — managed cluster conecta no hub, não o contrário | ACM 2.17 | Tech Preview | ~35 min |
| 8 | [Dashboards com o Red Hat Build of Perses](./08-GrafanaToPerses/README.md) | Dois caminhos: Parte 1 — COO genérico (`UIPlugin`/`PersesDashboard`, GA), isolado no cluster de cada aluno. Parte 2 — Multicluster Observability Add-on nativo do ACM (Technology Preview), dashboards de frota prontos, pré-configurado no hub | COO 1.5 / ACM 2.17 | GA + Tech Preview | ~30 min |
| 9 | [Helm Chart Direto de URL OCI/HTTPS no Console](./09-HelmConsoleOCI/README.md) **(backend validado, UI do console não)** | Instala um Helm chart sem cadastrar repositório antes — cola a URL `oci://` ou `https://` na hora | 4.22 | GA | ~15 min |
| 10 | [Gateway API](./10-GatewayAPI/README.md) | `GatewayClass` + `Gateway` + `HTTPRoute` — o `Gateway` gera seu próprio `Deployment`+`LoadBalancer`, comparado ao modelo clássico de Route/Router | 4.19+ | GA | ~20 min |

> **OCP 4.22** (lançado em 23 de junho de 2026, baseado no Kubernetes 1.35 "Timbernetes"):
> o In-place Pod Vertical Scaling (Lab 1) passou de Tech Preview para **GA**. Labs 7-10 cobrem
> outras novidades do 4.19-4.22 e do ACM 2.17/RHACS 4.11 (GitOps pull model, Perses, Helm
> Console, Gateway API) — marcados **"não validado ao vivo"** até serem testados num cluster
> real.
>
> **Labs removidos**: OLM v1 (exigia a capability opcional `OperatorLifecycleManagerV1`, que não
> vem habilitada por padrão e, uma vez ligada, não pode ser desligada de novo — não dava pra
> validar sem alterar permanentemente o cluster de testes deste repositório) e "Encontrando
> Problemas Antes de Atualizar o Cluster" (`oc adm upgrade recommend`).

---

## Automação via ACM

O diretório [`acm-hub/`](./acm-hub/README.md) contém as Policies do RHACM (Advanced Cluster
Management) usadas para preparar os clusters dos labs.

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
├── 01-InplacePodverticalscaling
│   ├── README.md
│   └── ocp-manifests
│       ├── 01-namespace.yaml
│       └── 02-deployment.yaml
├── 02-ExternalSecretsOperator
│   ├── README.md
│   └── ocp-manifests
│       ├── 00-namespace-app.yaml
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
├── 03-UserNamespaces
│   ├── README.md
│   └── ocp-manifests
│       ├── 01-namespace.yaml
│       ├── 02-deployment-no-userns.yaml
│       └── 03-deployment-with-userns.yaml
├── 04-ManagedBootImages
│   ├── README.md
│   └── ocp-manifests
│       └── 01-machine-configuration.yaml
├── 05-SigstoreImagePolicy
│   ├── README.md
│   └── ocp-manifests
│       ├── 01-namespace.yaml
│       ├── 02-deployment.yaml
│       ├── 03-imagepolicy-wrong-key.yaml
│       └── 04-imagepolicy-redhat-key.yaml
├── 06-VulnerabilitiesAndCRS
│   ├── README.md
│   └── ocp-manifests
│       ├── 01-namespace.yaml
│       └── 02-deployment.yaml
├── 07-GitOpsArgoAgent
│   ├── README.md
│   └── manifests
│       ├── 00-placement.yaml
│       ├── 01-gitopscluster-push.yaml
│       ├── 02-appset-push.yaml
│       ├── 03-push-rbac.yaml
│       ├── 04-argocd-agent-mode.yaml
│       ├── 05-appproject-wildcard.yaml
│       ├── 06-gitopscluster-agent.yaml
│       ├── 07-agent-view-rbac-policy.yaml
│       ├── 08-agent-write-rbac-policy.yaml
│       ├── 09-appset-pull.yaml
│       └── app
│           └── deployment.yaml
├── 08-GrafanaToPerses
│   ├── README.md
│   └── manifests
│       ├── 01-uiplugin-monitoring.yaml
│       ├── 02-perses-global-datasource.yaml
│       ├── 03-namespace.yaml
│       ├── 04-demo-deployment.yaml
│       └── 05-persesdashboard.yaml
├── 09-HelmConsoleOCI
│   └── README.md
├── 10-GatewayAPI
│   ├── README.md
│   └── manifests
│       ├── 01-gatewayclass.yaml
│       ├── 02-namespace.yaml
│       ├── 03-app.yaml
│       ├── 04-gateway.yaml
│       └── 05-httproute.yaml
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
        ├── policy-lab08.yaml
        └── policy-eso-oauth-secrets.yaml
```
