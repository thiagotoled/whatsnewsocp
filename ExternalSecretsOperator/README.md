# Exercício 2: External Secrets Operator no OpenShift 4.20+

Neste laboratório, você vai aprender a usar o **External Secrets Operator (ESO)** para integrar o OpenShift com o **Azure Key Vault**, sincronizando segredos de forma automática e bidirecional — sem precisar copiar valores manualmente.

O exercício está dividido em duas partes:
- **Parte 1 (ExternalSecret):** Buscar um segredo do Azure Key Vault e criá-lo automaticamente no OpenShift.
- **Parte 2 (PushSecret):** Publicar um segredo do OpenShift para o Azure Key Vault.

---

## Pré-requisitos

- OpenShift 4.18+ (ESO está disponível via OperatorHub no OCP 4.18+)
- Acesso a um Azure Key Vault com um Service Principal configurado
- CLI `oc` autenticado no cluster

---

## Parte 1: ExternalSecret — Puxando Segredos do Azure Key Vault

### Passo 1: Instalar o External Secrets Operator

Instale o operador via OperatorHub no console do OpenShift ou via CLI:

```bash
oc apply -f ExternalSecretsOperator/ocp-manifests/02-external-secrets-config.yaml
```

Aguarde o operador ficar disponível antes de prosseguir.

---

### Passo 2: Criar o Namespace e as Credenciais do Azure

Crie o namespace de demonstração e o Secret com as credenciais do Service Principal do Azure:

```bash
oc apply -f ExternalSecretsOperator/ocp-manifests/01-namespace.yaml
```

Edite o arquivo `03-azure-credentials-secret.yaml`, substituindo os placeholders `<AZURE_CLIENT_ID>` e `<AZURE_CLIENT_SECRET>` pelos valores reais, depois aplique:

```bash
oc apply -f ExternalSecretsOperator/ocp-manifests/03-azure-credentials-secret.yaml
```

---

### Passo 3: Criar o SecretStore

O `SecretStore` define **como** o ESO se conecta ao Azure Key Vault. Edite o arquivo `04-secret-store.yaml` substituindo:
- `<KEYVAULT_NAME>` — nome do seu Key Vault
- `<AZURE_TENANT_ID>` — ID do tenant Azure

```bash
oc apply -f ExternalSecretsOperator/ocp-manifests/04-secret-store.yaml
```

Verifique se o `SecretStore` está pronto:

```bash
oc get secretstore azure-store -n eso-demo
```

---

### Passo 4: Criar o ExternalSecret

O `ExternalSecret` define **qual** segredo buscar no Key Vault e com qual nome criá-lo no OpenShift. Neste exemplo, o segredo `demo-password` do Key Vault será criado como `demo-app-secret` no namespace `eso-demo`, com atualização automática a cada 1 minuto:

```bash
oc apply -f ExternalSecretsOperator/ocp-manifests/05-external-secret.yaml
```

Verifique se o `ExternalSecret` sincronizou com sucesso:

```bash
oc get externalsecret demo-app-es -n eso-demo
oc get secret demo-app-secret -n eso-demo
```

---

### Passo 5: Validar com um Pod de Teste

Crie um Pod que consome o segredo sincronizado como variável de ambiente:

```bash
oc apply -f ExternalSecretsOperator/ocp-manifests/06-pod-check.yaml
```

Verifique nos logs do Pod se o valor do segredo foi injetado corretamente:

```bash
oc logs secret-check -n eso-demo
```

A saída esperada é:
```
APP_PASSWORD=<valor-do-seu-segredo-no-keyvault>
```

---

## Parte 2: PushSecret — Publicando Segredos no Azure Key Vault

### Passo 1: Criar o Namespace e os Segredos de Origem

```bash
oc new-project app
```

Edite `07-push-source-secret.yaml` com o valor desejado para `password`, depois aplique:

```bash
oc apply -f ExternalSecretsOperator/ocp-manifests/07-push-source-secret.yaml
```

---

### Passo 2: Criar as Credenciais do Service Principal

Edite `08-push-azure-credentials.yaml` com o `ClientID` e `ClientSecret` do Service Principal, depois aplique:

```bash
oc apply -f ExternalSecretsOperator/ocp-manifests/08-push-azure-credentials.yaml
```

---

### Passo 3: Criar o SecretStore para o Namespace `app`

Edite `09-push-secret-store.yaml` substituindo `<KEYVAULT_NAME>` e `<AZURE_TENANT_ID>`, depois aplique:

```bash
oc apply -f ExternalSecretsOperator/ocp-manifests/09-push-secret-store.yaml
```

---

### Passo 4: Criar o PushSecret

O `PushSecret` publica o campo `password` do Secret `source-secret` no Azure Key Vault com o nome `minha-secret-na-keyvault`:

```bash
oc apply -f ExternalSecretsOperator/ocp-manifests/10-push-secret.yaml
```

Verifique o status do `PushSecret`:

```bash
oc get pushsecret push-local-secret-to-akv -n app
```

Acesse o Azure Key Vault e confirme que o segredo `minha-secret-na-keyvault` foi criado com o valor correto.

---

## Referências

- [Documentação oficial: External Secrets Operator no OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/security_and_compliance/external-secrets-operator-for-red-hat-openshift)
