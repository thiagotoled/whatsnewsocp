#!/usr/bin/env bash
set -euo pipefail

# Provisiona a infraestrutura Azure (Resource Group, Key Vault, role assignment + client secret
# num App Registration existente) usada pelo Lab 2 (External Secrets Operator). Rode UMA VEZ,
# antes do curso -- o Key Vault fica compartilhado por todos os alunos (cada aluno usa o próprio
# cluster/namespace, mas todos apontam pro mesmo Key Vault). Precisa do `az` autenticado
# (az login) com permissão pra criar resource group, Key Vault e role assignment na subscription.
#
# NOTA: `az ad sp create-for-rbac` está quebrado neste tipo de ambiente (bug conhecido do
# az-cli 2.81 com Python 3.14: "badly formed help string" em qualquer parser que toque
# --end-date). Além disso, criar uma App Registration nova pode falhar com "Insufficient
# privileges" se o tenant não permitir self-service app registration (era o caso aqui). Por
# isso este script reaproveita um App Registration/Service Principal JÁ EXISTENTE (ex.: o
# mesmo usado pelo policy-oauth-configuration) e só adiciona um client secret novo + a role
# Key Vault Secrets Officer -- não mistura o secret de login AAD com o de acesso ao Key Vault.
#
# Antes de rodar, defina:
#   EXISTING_APP_ID = appId do App Registration já existente (ex.: ecb2c027-2a5f-4324-9e05-3aa819ab351e)
#
# Os valores impressos no final vão nos placeholders de:
#   03-azure-credentials-secret.yaml / 08-push-azure-credentials.yaml
#     -> <AZURE_CLIENT_ID>, <AZURE_CLIENT_SECRET>
#   04-secret-store.yaml / 09-push-secret-store.yaml
#     -> <KEYVAULT_NAME>, <AZURE_TENANT_ID>
#
# IMPORTANTE (curso com vários alunos): a Parte 2 (PushSecret) escreve no MESMO Key Vault
# compartilhado. Cada aluno tem que usar um remoteKey único no 10-push-secret.yaml
# (padrão: minha-secret-na-keyvault_<nome-do-aluno>) -- senão um aluno sobrescreve o secret
# do outro. Ver a nota no README, Parte 2, Passo 4.

: "${EXISTING_APP_ID:?defina EXISTING_APP_ID com o appId do App Registration a reaproveitar}"

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-whatsnewsocp-eso-lab}"
LOCATION="${LOCATION:-eastus}"
KEYVAULT_NAME="${KEYVAULT_NAME:-kv-whatsnewsocp-$(openssl rand -hex 3)}"
DEMO_PASSWORD_VALUE="${DEMO_PASSWORD_VALUE:-SenhaDemo123!}"

echo "==> Criando resource group $RESOURCE_GROUP..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none

echo "==> Criando Key Vault $KEYVAULT_NAME (RBAC authorization)..."
az keyvault create \
  --name "$KEYVAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --enable-rbac-authorization true \
  -o none

KV_ID=$(az keyvault show --name "$KEYVAULT_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
SP_OBJECT_ID=$(az ad sp show --id "$EXISTING_APP_ID" --query id -o tsv)

echo "==> Dando role Key Vault Secrets Officer ao Service Principal existente ($EXISTING_APP_ID)..."
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets Officer" \
  --scope "$KV_ID" \
  -o none

echo "==> Gerando client secret novo, dedicado a este lab, no App Registration existente..."
CRED_JSON=$(az ad app credential reset --id "$EXISTING_APP_ID" --append --display-name "whatsnewsocp-eso-lab-$(date +%F)" --years 1 -o json)
CLIENT_ID=$(echo "$CRED_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['appId'])")
CLIENT_SECRET=$(echo "$CRED_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['password'])")

echo "==> Aguardando propagação de IAM (~20s)..."
sleep 20

echo "==> Dando a você mesmo (usuário atual) role Key Vault Secrets Officer, só pra poder semear o secret de teste..."
CALLER_ID=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$CALLER_ID" --assignee-principal-type User --role "Key Vault Secrets Officer" --scope "$KV_ID" -o none
sleep 20

echo "==> Semeando o secret demo-password (usado pela Parte 1 - ExternalSecret)..."
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name demo-password --value "$DEMO_PASSWORD_VALUE" -o none

cat <<EOF

==================================================================
Provisionamento concluído. Valores para os manifests do Lab 2:

  <KEYVAULT_NAME>       = $KEYVAULT_NAME
  <AZURE_TENANT_ID>     = $TENANT_ID
  <AZURE_CLIENT_ID>     = $CLIENT_ID
  <AZURE_CLIENT_SECRET> = $CLIENT_SECRET

Guarde o CLIENT_SECRET agora -- o Azure não deixa recuperar depois (só rotacionar).

Secret de teste no Key Vault: demo-password = $DEMO_PASSWORD_VALUE
==================================================================
EOF
