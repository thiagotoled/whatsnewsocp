# Exercício 1: In-place Pod Vertical Scaling no OpenShift 4.20+

O In-place Pod Vertical Scaling permite ajustar CPU e memória de um Pod em execução **sem reiniciá-lo** (Tech Preview no OCP 4.20, GA no 4.22 / Kubernetes 1.35). Este lab demonstra o procedimento completo de scale-up e scale-down, ideal para aplicações que não toleram downtime apenas para *rightsizing*.

---

##  Passo 1: Conectar ao Cluster e Aplicar os Manifestos

1. Certifique-se de estar logado no seu cluster OpenShift via CLI (`oc login`).
2. Aplique os manifestos do repositório para criar o Namespace e o Deployment:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/01-InplacePodverticalscaling/ocp-manifests/01-namespace.yaml
```

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/01-InplacePodverticalscaling/ocp-manifests/02-deployment.yaml
```


3. Verifique se o Pod está rodando e **observe o tempo de vida (AGE)** e o ID do container:

```bash
oc get pods -n lab-inplace-scaling
```

---

##  Passo 2: Monitorar em Tempo Real (Abra um novo terminal)

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

Capture o nome do Pod e execute o patch:

```bash
POD=$(oc get pod -n lab-inplace-scaling -l app=nginx-inplace -o jsonpath='{.items[0].metadata.name}')

oc patch pod "$POD" -p '{"spec": {"containers": [{"name": "nginx", "resources": { "requests" :{ "cpu" : "300m", "memory": "256Mi"}, "limits" :{ "cpu" : "500m", "memory" : "512Mi" } } }] }}' --subresource=resize -n lab-inplace-scaling
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

O processo inverso também é suportado — CPU e memória, request e limit, tudo pra baixo,
ainda 100% sem restart:

```bash
oc patch pod "$POD" -p '{"spec": {"containers": [{"name": "nginx", "resources": { "requests" :{ "cpu" : "100m", "memory": "128Mi"}, "limits" :{ "cpu" : "200m", "memory" : "412Mi" } } }] }}' --subresource=resize -n lab-inplace-scaling
```

###  Verificação Final:

Confirme novamente que os recursos foram alterados com sucesso e o container permaneceu online o tempo todo:

```bash
oc get pod -n lab-inplace-scaling -l app=nginx-inplace -o jsonpath='{.items[0].spec.containers[0].resources}' ; echo
oc describe pod -n lab-inplace-scaling -l app=nginx-inplace | grep -A 5 Requests
```

---

## Referências

* [In-Place Pod Resize (KEP-1287)](https://github.com/kubernetes/enhancements/tree/master/keps/sig-node/1287-in-place-update-pod-resources)
* [Documentação oficial: Pod vertical scaling no OCP 4.22](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/nodes/pods#nodes-pods-vertical-scaling)
