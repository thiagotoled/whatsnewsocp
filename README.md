# What's New in OpenShift — Laboratórios Práticos

Repositório com exercícios práticos sobre as novidades do **Red Hat OpenShift 4.20+**.  
Cada diretório contém um laboratório independente com manifestos prontos para aplicar no cluster.

---

## Exercícios Disponíveis

| # | Exercício | Descrição |
|---|-----------|-----------|
| 1 | [In-place Pod Vertical Scaling](./InplacePodverticalscaling/README.md) | Ajuste de CPU e Memória de Pods em execução **sem reinicialização** |
| 2 | [External Secrets Operator](./ExternalSecretsOperator/README.md) | Sincronização bidirecional de segredos entre OpenShift e Azure Key Vault |

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
└── ExternalSecretsOperator/
    ├── README.md
    └── ocp-manifests/
        ├── 01-namespace.yaml
        ├── 02-external-secrets-config.yaml
        ├── 03-azure-credentials-secret.yaml
        ├── 04-secret-store.yaml
        ├── 05-external-secret.yaml
        ├── 06-pod-check.yaml
        ├── 07-push-source-secret.yaml
        ├── 08-push-azure-credentials.yaml
        ├── 09-push-secret-store.yaml
        └── 10-push-secret.yaml
```
