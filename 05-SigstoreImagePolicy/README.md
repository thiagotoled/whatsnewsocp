# Exercício 5: Verificação de Assinatura de Imagens com Sigstore (`ImagePolicy`)

Neste laboratório, você vai usar o `ImagePolicy` (GA no OpenShift 4.20) pra exigir que imagens
de um determinado registry/repositório estejam assinadas via **sigstore** antes de serem
puxadas pelos nós, e vai ver, na prática, o CRI-O **recusar** uma imagem que não bate com a
assinatura esperada, num escopo restrito a **um único namespace**.

---

## Conceito Rápido

O `ImagePolicy` (`config.openshift.io/v1`, **namespace-scoped**) e o `ClusterImagePolicy`
(mesma API, **cluster-scoped**) definem **escopos** de imagem (registry, repo ou imagem exata) e
uma **raiz de confiança** (`rootOfTrust`) pra verificar assinaturas sigstore antes do pull:

- `PublicKey`: verifica contra uma chave pública sigstore/cosign (o que este lab usa)
- `PKI`: Bring Your Own PKI, cadeia de CA própria (Tech Preview, atrás do feature gate
  `SigstoreImageVerificationPKI`)
- `FulcioCAWithRekor`: keyless, via Fulcio + Rekor públicos do projeto Sigstore

> **`ImagePolicy` vs `ClusterImagePolicy`**: mesmo schema, diferença só no escopo. O
> `ImagePolicy` deste lab só afeta pods do namespace `lab-sigstore-policy`. Pra exigir a mesma
> assinatura de **qualquer** pod do cluster (incluindo operadores e outros namespaces), o
> objeto seria `kind: ClusterImagePolicy`, sem `metadata.namespace`, o resto do YAML é
> idêntico. Tem uma regra de precedência entre os dois: se o mesmo escopo aparecer nos dois ao
> mesmo tempo, o `ClusterImagePolicy` sempre vence sobre o `ImagePolicy` do namespace.

**Ponto importante**: a verificação **não** acontece no admission da API do Kubernetes. Ela
acontece no **CRI-O, no nó, durante o pull da imagem**. Isso significa duas coisas na prática,
mesmo o `ImagePolicy` sendo namespace-scoped:

1. Um `oc apply` de um Deployment com imagem não-conforme **não falha na hora**. O Pod é criado
   normalmente e só falha depois, quando o kubelet tenta puxar a imagem: o sintoma é
   `ImagePullBackOff` com um evento `SignatureValidationFailed`.
2. Criar ou mudar um `ImagePolicy` **dispara um rollout de `MachineConfig`** em **todos os nós
   do cluster** (não só onde o Pod vai rodar): o MCO precisa reescrever a configuração de
   assinatura do CRI-O em todo lugar, mesmo a policy valendo só pra um namespace. Isso leva
   minutos, não segundos.

Este lab usa a imagem `registry.access.redhat.com/ubi9/ubi-micro` de propósito: ela **já vem
assinada de verdade pela Red Hat** via sigstore. Isso permite montar os dois lados do lab (chave
errada bloqueia, chave certa libera) **sem precisar instalar `cosign` nem assinar nada**, só
trocar a chave pública na policy.

---

## Pré-requisitos

- Acesso de **cluster-admin** (mesmo o `ImagePolicy` sendo namespace-scoped, criar/editar um
  ainda depende do rollout de `MachineConfig` nos nós)
- OpenShift 4.20+ (feature gate `SigstoreImageVerification` já vem habilitado por padrão)
- CLI `oc` autenticado

---

## Passo 1: Linha de Base (Sem Nenhuma Policy)

> **Criado por política**: se seu cluster foi importado no hub com ACM, o namespace
> `lab-sigstore-policy` e o `Deployment demo-app` já vêm pré-criados pelo `policy-lab05` — pule
> os dois `oc apply` abaixo e vá direto pro `oc get pods` de verificação.

Sem ACM, aplique o namespace e o Deployment. Ele usa a imagem `ubi9/ubi-micro`, que vamos
"proteger" nos próximos passos:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/05-SigstoreImagePolicy/ocp-manifests/01-namespace.yaml
```

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/05-SigstoreImagePolicy/ocp-manifests/02-deployment.yaml
```

Confirme que sobe normal, sem policy nenhuma no caminho:

```bash
oc get pods -n lab-sigstore-policy
```

Saída esperada:

```
NAME                        READY   STATUS    RESTARTS   AGE
demo-app-xxxxxxxxxx-xxxxx   1/1     Running   0          20s
```

---

## Passo 2: Aplicar a Policy com uma Chave Errada

O [`03-imagepolicy-wrong-key.yaml`](ocp-manifests/03-imagepolicy-wrong-key.yaml) exige, só dentro do namespace `lab-sigstore-policy`, que
qualquer imagem de `registry.access.redhat.com/ubi9/ubi-micro` esteja assinada com uma chave EC
gerada só pra este lab (`openssl ecparam -genkey -name prime256v1`), que **não** é a chave real
que assinou a imagem:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/05-SigstoreImagePolicy/ocp-manifests/03-imagepolicy-wrong-key.yaml
```

Acompanhe o rollout nos nós (isso demora: no teste, levou alguns minutos):

```bash
oc get mcp -w
```

Espere `UPDATED=True` e `UPDATING=False` em todos os pools antes de continuar.

---

## Passo 3: Ver o Bloqueio Acontecer

Force um novo pull recriando o Pod (o CRI-O só reavalia a assinatura no momento do pull, não
em Pods já rodando). `oc get pods -w` fica esperando pra sempre um estado `Running` que não vai
chegar (o objetivo aqui é justamente o Pod falhar) — confirme o estado com um `get` simples em
vez de deixar o watch travado:

```bash
oc get pods -n lab-sigstore-policy -l app=demo-app
```

Se já estiver `Running` (Pod antigo, de antes da policy), force a recriação:

```bash
oc delete pod -n lab-sigstore-policy -l app=demo-app
oc get pods -n lab-sigstore-policy -l app=demo-app
```

O novo Pod deve ficar em `ImagePullBackOff`. Veja o evento:

```bash
oc describe pod -n lab-sigstore-policy -l app=demo-app
```

Saída esperada (resumida). Note o `SignatureValidationFailed` e as tentativas de verificação
criptográfica falhando:

```
Warning  Failed  kubelet  Failed to pull image "registry.access.redhat.com/ubi9/ubi-micro:latest":
SignatureValidationFailed: unable to pull image or OCI artifact: pull image err: copying system
image from manifest list: Source image rejected: None of the signatures were accepted, reasons:
cryptographic signature verification failed: ...
Warning  Failed  kubelet  Error: SignatureValidationFailed
```

Isso confirma que a imagem **tem** assinatura sigstore de verdade, só não bate com a chave que
configuramos.

---

## Passo 4: Corrigir com a Chave Real da Red Hat

O [`04-imagepolicy-redhat-key.yaml`](ocp-manifests/04-imagepolicy-redhat-key.yaml) é o mesmo `ImagePolicy` (mesmo `name`/`namespace`, é um
update), trocando a chave pela chave de release oficial da Red Hat, publicada em
[security.access.redhat.com/data/63405576.txt](https://security.access.redhat.com/data/63405576.txt):

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/05-SigstoreImagePolicy/ocp-manifests/04-imagepolicy-redhat-key.yaml
```

De novo, espere o rollout do `MachineConfig` terminar (`oc get mcp -w`). O Pod atual ainda está
em `ImagePullBackOff` do Passo 3 — force a recriação (de novo, evite `-w` aqui: o Pod que já
está em erro não vai virar `Running` sozinho, só o novo depois do delete):

```bash
oc delete pod -n lab-sigstore-policy -l app=demo-app
oc get pods -n lab-sigstore-policy -l app=demo-app
```

Dessa vez o Pod deve subir normal:

```
NAME                        READY   STATUS    RESTARTS   AGE
demo-app-xxxxxxxxxx-xxxxx   1/1     Running   0          15s
```

Confira o evento de sucesso:

```bash
oc describe pod -n lab-sigstore-policy -l app=demo-app
```

```
Normal  Pulling  kubelet  Pulling image "registry.access.redhat.com/ubi9/ubi-micro:latest"
Normal  Pulled   kubelet  Successfully pulled image "registry.access.redhat.com/ubi9/ubi-micro:latest" ...
```

---

## Passo 5: Limpeza

Remover o `ImagePolicy` também dispara um novo rollout de `MachineConfig` (reverte o CRI-O pra
não exigir mais assinatura nesse escopo). Espere terminar antes de considerar o cluster
"limpo":

```bash
oc delete imagepolicy lab-require-signature -n lab-sigstore-policy
oc delete namespace lab-sigstore-policy
oc get mcp -w
```

---

## Referências

- [ImagePolicy \[config.openshift.io/v1\] — Config APIs — OpenShift 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/config_apis/imagepolicy-config-openshift-io-v1)
- [ClusterImagePolicy \[config.openshift.io/v1\] — Config APIs — OpenShift 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/config_apis/clusterimagepolicy-config-openshift-io-v1)
- [Chapter 12. Manage secure signatures with sigstore — Nodes — OpenShift 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/nodes/nodes-sigstore-using)
- [Verify Cosign bring-your-own PKI signature on OpenShift — Red Hat Developer](https://developers.redhat.com/articles/2025/09/08/verify-cosign-bring-your-own-pki-signature-openshift)
- [Chave de release da Red Hat usada neste lab](https://security.access.redhat.com/data/63405576.txt)
