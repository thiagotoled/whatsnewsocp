# Exercício 3: User Namespaces no OpenShift 4.20+

Neste laboratório, você vai entender como o **User Namespaces** isola a identidade de processos dentro de um container do usuário real no nó host. Com `hostUsers: false`, um processo que roda como `root` (UID 0) dentro do container é mapeado para um UID sem privilégio no host — reduzindo drasticamente a superfície de ataque em caso de escape de container.

---

## Conceito Rápido

| Cenário | UID no container | UID no host |
|---------|-----------------|-------------|
| `hostUsers: true` (padrão) | 0 (root) | 0 (root) |
| `hostUsers: false` | 0 (root) | 65536+ (sem privilégio) |

Com User Namespaces ativado, mesmo que um atacante escape do container, o processo chega ao host como um usuário sem privilégios.

---

## Passo 1: Criar o Namespace e Aplicar os Deployments

```bash
oc apply -f UserNamespaces/ocp-manifests/01-namespace.yaml
```

Aplique os dois Deployments — um **sem** isolamento e outro **com** User Namespaces para comparação:

```bash
oc apply -f UserNamespaces/ocp-manifests/02-deployment-no-userns.yaml
oc apply -f UserNamespaces/ocp-manifests/03-deployment-with-userns.yaml
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

Saída esperada — UID 0 mapeado diretamente para o host:
```
uid=0(root) gid=0(root) groups=0(root)
         0          0 4294967295
         0          0 4294967295
```

O processo roda como `root` no host. Se escapar do container, tem privilégios totais no nó.

---

## Passo 3: Validar o Deployment COM User Namespaces (`hostUsers: false`)

Acesse o Pod com isolamento ativado:

```bash
oc exec -n userns-lab deploy/userns-demo-isolated -- id
oc exec -n userns-lab deploy/userns-demo-isolated -- cat /proc/self/uid_map
oc exec -n userns-lab deploy/userns-demo-isolated -- cat /proc/self/gid_map
```

Saída esperada — UID 0 dentro do container mapeado para UID alto no host:
```
uid=0(root) gid=0(root) groups=0(root)
         0      65536      65536
         0      65536      65536
```

Dentro do container o processo se vê como `root`, mas no host ele é `UID 65536` — sem nenhum privilégio.

---

## Referências

- [Documentação oficial: User Namespaces no OCP 4.20](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/nodes/nodes-pods-user-namespaces)
