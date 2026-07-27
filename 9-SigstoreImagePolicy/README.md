# Exercício 9: Verificação de Assinatura de Imagens com Sigstore (`ClusterImagePolicy`)

Neste laboratório, você vai usar o `ClusterImagePolicy` (GA no OpenShift 4.20) pra exigir que
imagens de um determinado registry/repositório estejam assinadas via **sigstore** antes de
serem puxadas pelos nós — e vai ver, na prática, o CRI-O **recusar** uma imagem que não bate
com a assinatura esperada.

---

## Conceito Rápido

O `ClusterImagePolicy` (`config.openshift.io/v1`, cluster-scoped) e o `ImagePolicy`
(namespace-scoped, mesma API) definem **escopos** de imagem (registry, repo ou imagem exata) e
uma **raiz de confiança** (`rootOfTrust`) pra verificar assinaturas sigstore antes do pull:

- `PublicKey` — verifica contra uma chave pública sigstore/cosign (o que este lab usa)
- `PKI` — Bring Your Own PKI, cadeia de CA própria (Tech Preview, atrás do feature gate
  `SigstoreImageVerificationPKI`)
- `FulcioCAWithRekor` — keyless, via Fulcio + Rekor públicos do projeto Sigstore

**Ponto importante**: a verificação **não** acontece no admission da API do Kubernetes — ela
acontece no **CRI-O, no nó, durante o pull da imagem**. Isso significa duas coisas na prática:

1. Um `oc apply` de um Deployment com imagem não-conforme **não falha na hora**. O Pod é criado
   normalmente e só falha depois, quando o kubelet tenta puxar a imagem — o sintoma é
   `ImagePullBackOff` com um evento `SignatureValidationFailed`.
2. Criar ou mudar um `ClusterImagePolicy` **dispara um rollout de `MachineConfig`** em **todos
   os nós do cluster** (masters e workers, não só onde a imagem vai rodar) — o MCO precisa
   reescrever a configuração de assinatura do CRI-O. Isso leva minutos, não segundos.

Este lab usa a imagem `registry.access.redhat.com/ubi9/ubi-micro` de propósito: ela **já vem
assinada de verdade pela Red Hat** via sigstore. Isso permite montar os dois lados do lab (chave
errada bloqueia, chave certa libera) **sem precisar instalar `cosign` nem assinar nada** — só
trocar a chave pública na policy.

---

## Pré-requisitos

- Acesso de **cluster-admin** (o `ClusterImagePolicy` é cluster-scoped)
- OpenShift 4.20+ (feature gate `SigstoreImageVerification` já vem habilitado por padrão)
- CLI `oc` autenticado

---

## Passo 1: Linha de Base — Sem Nenhuma Policy

Aplique o namespace e o Deployment. Ele usa a imagem `ubi9/ubi-micro`, que vamos "proteger"
nos próximos passos:

```bash
oc apply -f 9-SigstoreImagePolicy/ocp-manifests/01-namespace.yaml
oc apply -f 9-SigstoreImagePolicy/ocp-manifests/02-deployment.yaml
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

O `03-clusterimagepolicy-wrong-key.yaml` exige que qualquer imagem de
`registry.access.redhat.com/ubi9/ubi-micro` esteja assinada com uma chave EC gerada só pra
este lab (`openssl ecparam -genkey -name prime256v1`) — que **não** é a chave real que assinou
a imagem:

```bash
oc apply -f 9-SigstoreImagePolicy/ocp-manifests/03-clusterimagepolicy-wrong-key.yaml
```

Acompanhe o rollout nos nós (isso demora — no teste, levou alguns minutos em masters **e**
workers):

```bash
oc get mcp -w
```

Espere `UPDATED=True` e `UPDATING=False` em todos os pools antes de continuar.

---

## Passo 3: Ver o Bloqueio Acontecer

Force um novo pull recriando o Pod (o CRI-O só reavalia a assinatura no momento do pull, não
em Pods já rodando):

```bash
oc delete pod -n lab-sigstore-policy -l app=demo-app
```

Acompanhe:

```bash
oc get pods -n lab-sigstore-policy -w
```

O novo Pod deve ficar em `ImagePullBackOff`. Veja o evento:

```bash
oc describe pod -n lab-sigstore-policy -l app=demo-app
```

Saída esperada (resumida) — note o `SignatureValidationFailed` e as tentativas de verificação
criptográfica falhando:

```
Warning  Failed  kubelet  Failed to pull image "registry.access.redhat.com/ubi9/ubi-micro:latest":
SignatureValidationFailed: unable to pull image or OCI artifact: pull image err: copying system
image from manifest list: Source image rejected: None of the signatures were accepted, reasons:
cryptographic signature verification failed: ...
Warning  Failed  kubelet  Error: SignatureValidationFailed
```

Isso confirma que a imagem **tem** assinatura sigstore de verdade — só não bate com a chave que
configuramos.

---

## Passo 4: Corrigir com a Chave Real da Red Hat

O `04-clusterimagepolicy-redhat-key.yaml` é o mesmo `ClusterImagePolicy` (mesmo `name`, é um
update), trocando a chave pela chave de release oficial da Red Hat, publicada em
[security.access.redhat.com/data/63405576.txt](https://security.access.redhat.com/data/63405576.txt):

```bash
oc apply -f 9-SigstoreImagePolicy/ocp-manifests/04-clusterimagepolicy-redhat-key.yaml
```

De novo, espere o rollout do `MachineConfig` terminar (`oc get mcp -w`), e force um novo pull:

```bash
oc delete pod -n lab-sigstore-policy -l app=demo-app
oc get pods -n lab-sigstore-policy -w
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

Remover o `ClusterImagePolicy` também dispara um novo rollout de `MachineConfig` (reverte o
CRI-O pra não exigir mais assinatura nesse escopo) — espere terminar antes de considerar o
cluster "limpo":

```bash
oc delete clusterimagepolicy lab-require-signature
oc delete namespace lab-sigstore-policy
oc get mcp -w
```

---

## Referências

- [ClusterImagePolicy \[config.openshift.io/v1\] — Config APIs — OpenShift 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/config_apis/clusterimagepolicy-config-openshift-io-v1)
- [Chapter 12. Manage secure signatures with sigstore — Nodes — OpenShift 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/nodes/nodes-sigstore-using)
- [Verify Cosign bring-your-own PKI signature on OpenShift — Red Hat Developer](https://developers.redhat.com/articles/2025/09/08/verify-cosign-bring-your-own-pki-signature-openshift)
- [Chave de release da Red Hat usada neste lab](https://security.access.redhat.com/data/63405576.txt)
