# Exercício 3: User Namespaces no OpenShift 4.20+

Com `hostUsers: false`, um processo que roda como `root` (UID 0) dentro do container é mapeado para um UID sem privilégio no host, reduzindo a superfície de ataque em caso de escape. Este lab compara os dois cenários na prática: um Deployment com **User Namespaces** e outro sem.

---

## Conceito Rápido

| Cenário | UID no container | UID no host |
|---------|-----------------|-------------|
| `hostUsers: true` (padrão) | 0 (root) | 0 (root) |
| `hostUsers: false` | 0 (root) | 65536+ (sem privilégio) |

Com User Namespaces ativado, mesmo que um atacante escape do container, o processo chega ao host como um usuário sem privilégios.

---

## Passo 1: Criar o Namespace e Aplicar os Deployments

> **Criado por política**: se seu cluster foi importado no hub com ACM, o namespace
> `userns-lab` já vem pré-criado pelo `policy-lab03` — pule o `oc apply` abaixo.

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/03-UserNamespaces/ocp-manifests/01-namespace.yaml
```

Aplique os dois Deployments: um **sem** isolamento e outro **com** User Namespaces para comparação:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/03-UserNamespaces/ocp-manifests/02-deployment-no-userns.yaml
```

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/03-UserNamespaces/ocp-manifests/03-deployment-with-userns.yaml
```

Aguarde os Pods ficarem prontos:

```bash
oc get pods -n userns-lab
```

---

## Passo 2: Validar o Deployment SEM User Namespaces (`hostUsers: true`)

Acesse o Pod padrão e verifique a identidade do processo:

```bash
oc exec -n userns-lab deploy/userns-demo-host -- id
oc exec -n userns-lab deploy/userns-demo-host -- cat /proc/self/uid_map
oc exec -n userns-lab deploy/userns-demo-host -- cat /proc/self/gid_map
```

Saída esperada: UID 0 mapeado diretamente para o host:
```
uid=0(root) gid=0(root) groups=0(root)
         0          0 4294967295
         0          0 4294967295
```

O processo roda como `root` no host. Se escapar do container, tem privilégios totais no nó.

> **Por que o manifesto concede SCC `anyuid`?** Sem isso, o `restricted-v2` (SCC padrão do
> OpenShift) força um UID alto não-privilegiado mesmo com `hostUsers: true`, e o `id` mostraria
> algo como `uid=1000770000`, não `uid=0(root)`. Pra comparação fazer sentido (rodar como root
> DE VERDADE de um lado, isolado do outro), o Deployment sem User Namespaces também precisa de
> `anyuid` + `runAsUser: 0` explícitos. Confirmado ao vivo: sem isso o "antes" do lab nunca
> mostra root de verdade.

---

## Passo 3: Validar o Deployment COM User Namespaces (`hostUsers: false`)

Acesse o Pod com isolamento ativado:

```bash
oc exec -n userns-lab deploy/userns-demo-isolated -- id
oc exec -n userns-lab deploy/userns-demo-isolated -- cat /proc/self/uid_map
oc exec -n userns-lab deploy/userns-demo-isolated -- cat /proc/self/gid_map
```

Saída esperada: UID 0 dentro do container mapeado para um UID alto no host:
```
uid=0(root) gid=0(root) groups=0(root)
         0 3093037056      65536
         0 3093037056      65536
```

Dentro do container o processo se vê como `root`, mas no host ele é um UID sem privilégio
nenhum. O segundo número do `uid_map` (o offset, `3093037056` no teste ao vivo) **não é fixo**:
o kubelet/CRI-O aloca uma faixa de 65536 UIDs por Pod a partir de um pool grande e reservado
para User Namespaces, então o offset exato varia a cada Pod recriado. O que importa é que ele
está bem longe de qualquer UID real do sistema, não o valor específico.

---

## Referências

- [Documentação oficial: User Namespaces no OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/nodes/nodes-pods-user-namespaces)
