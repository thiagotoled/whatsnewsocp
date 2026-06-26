# Exercício 1: In-place Pod Vertical Scaling no OpenShift 4.20+

Neste laboratório, você vai aprender a modificar os recursos de CPU e Memória de uma aplicação em execução **sem que o Pod precise ser reiniciado**. Isso é ideal para aplicações críticas que não podem sofrer downtime apenas para ajuste de tamanho (*rightsizing*).

---

##  Passo 1: Conectar ao Cluster e Aplicar os Manifestos

1. Certifique-se de estar logado no seu cluster OpenShift via CLI (`oc login`).
2. Aplique os manifestos do repositório para criar o Namespace e o Deployment:

```bash
oc apply -f InplacePodverticalscaling/ocp-manifests/01-namespace.yaml
oc apply -f InplacePodverticalscaling/ocp-manifests/02-deployment.yaml
```

3. Verifique se o Pod está rodando e **observe o tempo de vida (AGE)** e o ID do container:

```bash
oc get pods -n lab-inplace-scaling
```

---

## 👀 Passo 2: Monitorar em Tempo Real (Abra um novo terminal)

Abra uma nova janela de terminal e execute o comando abaixo para monitorar os recursos e o status do Pod continuamente:

```bash
oc get pod -n lab-inplace-scaling -l app=nginx-inplace -w
```

*(Deixe esse terminal aberto de lado e observando).*

---

##  Passo 3: Realizar o Scale-Up (Aumentar Recursos)

Vamos aumentar os recursos do container de forma dinâmica usando o comando `oc patch`. 

* **CPU:** De `100m/200m` para `300m/500m`
* **Memória:** De `128Mi/256Mi` para `256Mi/512Mi`

Execute o seguinte comando no seu terminal principal:

```bash
oc patch deployment nginx-inplace -n lab-inplace-scaling --type=json -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources",
    "value": {
      "requests": {"cpu": "300m", "memory": "256Mi"},
      "limits": {"cpu": "500m", "memory": "512Mi"}
    }
  }
]'
```

###  O que verificar agora?

1. Olhe o terminal onde o comando com `-w` estava rodando. O Pod **não** entrou em estado de `Terminating` ou `ContainerCreating`.
2. Execute o comando abaixo e veja que o campo `RESTARTS` continua em `0` e o **AGE** do Pod não resetou:

```bash
oc get pods -n lab-inplace-scaling
```

3. Verifique se o OpenShift já atualizou os limites internos inspecionando o Pod:

```bash
oc describe pod -n lab-inplace-scaling -l app=nginx-inplace | grep -A 5 Requests
```

---

##  Passo 4: Realizar o Scale-Down (Diminuir Recursos)

O processo inverso também é suportado. Vamos reduzir os recursos de volta para o estado inicial para economizar capacidade do cluster.

Execute o comando de patch para diminuir:

```bash
oc patch deployment nginx-inplace -n lab-inplace-scaling --type=json -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources",
    "value": {
      "requests": {"cpu": "100m", "memory": "128Mi"},
      "limits": {"cpu": "200m", "memory": "256Mi"}
    }
  }
]'
```

###  Verificação Final:

Confirme novamente que os recursos foram alterados com sucesso e o container permaneceu online o tempo todo:

```bash
oc get pod -n lab-inplace-scaling -l app=nginx-inplace -o jsonpath='{.items[0].spec.containers[0].resources}'
```
