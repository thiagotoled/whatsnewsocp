# Exercício 12: Gateway API — Dois Gateways, Dois LoadBalancers Independentes

> **Validado ao vivo em OCP 4.22.8**: os 8 manifestos deste lab (`GatewayClass`, namespace, 2
> apps, 2 `Gateway`s, 2 `HTTPRoute`s) foram aplicados de ponta a ponta num cluster real. Achado
> importante que corrige a primeira versão deste README: **não precisa de OpenShift Service
> Mesh Operator instalado** — nesse cluster, sem nenhum CSV de Service Mesh/Istio/Sail presente,
> o `GatewayClass openshift-default` foi `Accepted` sozinho e um `istiod` (v1.28.5) subiu
> automaticamente em `openshift-ingress`, gerenciado pelo próprio Ingress Operator (`status`
> mostra `reason: ManagedByCIO` — Cluster Ingress Operator). Os dois `Gateway`s programaram com
> IP próprio (`PROGRAMMED: True`) em menos de 2 minutos.

Neste laboratório, você vai subir **dois `Gateway` completamente independentes** no mesmo
cluster — cada um com seu próprio `Deployment` e `Service` do tipo `LoadBalancer` — e comparar
isso com o modelo clássico do Route/Router do OpenShift.

> **Cada aluno no próprio cluster**: este lab não depende de ACM nem do hub — é Gateway API
> puro do OpenShift, isolado. Sem naming por aluno, sem hub compartilhado.

---

## Conceito Rápido

O Gateway API é a evolução **Kubernetes-nativa** do Ingress — parte do projeto upstream
`gateway-api`, não específico do OpenShift (diferente do `Route`, que é uma API só da Red Hat).
No OpenShift, a API/CRDs vêm via Ingress Operator (GA desde o 4.19), e quem reconcilia os
objetos `Gateway` é um `istiod` (baseado em Istio) — **confirmado ao vivo que o próprio Ingress
Operator já provisiona esse `istiod` sozinho quando o primeiro `GatewayClass` é criado**, sem
precisar instalar o OpenShift Service Mesh Operator à parte (isso corrige o que uma pesquisa
sem doc oficial completa sugeria antes).

- **`GatewayClass`**: cluster-scoped, define **qual controller** implementa os `Gateway`s que o
  referenciam (`controllerName: openshift.io/gateway-controller/v1`). É o "sabor" de gateway —
  dá pra ter mais de um `GatewayClass` (ex.: um pra tráfego público, outro pra interno), cada
  um potencialmente com um controller/implementação diferente.
- **`Gateway`**: sempre no namespace `openshift-ingress`, referencia um `GatewayClass`. **Cada
  `Gateway` gera seu próprio `Deployment` + `Service LoadBalancer`** (nome padrão
  `<gateway-name>-<gatewayclass-name>`) — isso é o que permite ter múltiplas instâncias
  isoladas, cada uma com seu próprio IP/hostname externo.
- **`HTTPRoute`**: vive no namespace da **aplicação** (não em `openshift-ingress`), referencia
  um `Gateway` via `parentRefs`. É aqui que o modelo de responsabilidade muda: o time de
  infraestrutura é dono do `Gateway`, o time de aplicação é dono do `HTTPRoute` no próprio
  namespace — sem precisar de permissão pra mexer em `openshift-ingress`.

> **Por que criar dois `Gateway`s em vez de um só**: não é só sobre isolamento de tráfego — é
> sobre prática. Criar um `Gateway` é, na prática, o equivalente em Gateway API de provisionar
> um novo `IngressController`: gera um `Deployment` e um `Service LoadBalancer` do zero, do
> jeito clássico já ensinado em outros exercícios deste curso. Fazer isso duas vezes (uma por
> app) dá ao aluno a repetição desse fluxo de provisionamento, não só o resultado final.

> **Isso não é a única forma de ter múltiplos pontos de entrada no OpenShift**: o `Route`/
> `IngressController` clássico já suporta sharding (vários routers). O diferencial real do
> Gateway API é ser uma API **portável** (mesmo YAML funciona em outro Kubernetes, não só
> OpenShift) e ter esse modelo de responsabilidade mais granular entre infra e aplicação — não
> é que o clássico "não consegue" ter mais de um ponto de entrada.

---

## Pré-requisitos

- **OpenShift Service Mesh Operator 3.0+** instalado no cluster (instrutor/você, uma vez —
  fora do escopo deste lab detalhar a instalação do operator em si).
- Acesso de administrador de cluster (pra criar `GatewayClass`, cluster-scoped, e recursos em
  `openshift-ingress`).

---

## Passo 1: Confirmar/Criar o `GatewayClass`

```bash
oc get gatewayclass
```

Se `openshift-default` já aparecer na lista, pule a criação. Senão:

```bash
oc apply -f 11-GatewayAPI/manifests/01-gatewayclass.yaml
oc get gatewayclass openshift-default -o jsonpath='{.status.conditions}' | jq .
```

Espere a condição `Accepted: "True"`.

---

## Passo 2: Subir as Duas Apps de Exemplo

```bash
oc apply -f 11-GatewayAPI/manifests/02-namespace.yaml
oc apply -f 11-GatewayAPI/manifests/03-app-a.yaml
oc apply -f 11-GatewayAPI/manifests/04-app-b.yaml
oc get pods -n lab-gateway-demo
```

Duas apps idênticas de propósito ("Hello OpenShift") — o ponto do lab é o roteamento, não o
conteúdo das respostas.

---

## Passo 3: Criar os Dois `Gateway`s

```bash
oc apply -f 11-GatewayAPI/manifests/05-gateway-a.yaml
oc apply -f 11-GatewayAPI/manifests/06-gateway-b.yaml
```

Confirme que **cada um** gerou seu próprio `Deployment` e `Service LoadBalancer`, separados:

```bash
oc get deployment -n openshift-ingress | grep gateway-app
oc get svc -n openshift-ingress | grep gateway-app
```

Anote os dois `EXTERNAL-IP`/hostname — vão ser diferentes um do outro.

---

## Passo 4: Criar os `HTTPRoute`s e Testar

```bash
oc apply -f 11-GatewayAPI/manifests/07-httproute-a.yaml
oc apply -f 11-GatewayAPI/manifests/08-httproute-b.yaml
```

Como os hostnames (`app-a.gwapi.example.com`, `app-b.gwapi.example.com`) não têm DNS real
apontando pra eles (diferente do `Route` clássico, que ganha um subdomínio automático em
`*.apps.<seu-domínio>`), teste direto contra o IP/hostname de cada `LoadBalancer`, informando
o `Host` manualmente:

```bash
LB_A=$(oc get svc -n openshift-ingress -l gateway.networking.k8s.io/gateway-name=gateway-app-a -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
LB_B=$(oc get svc -n openshift-ingress -l gateway.networking.k8s.io/gateway-name=gateway-app-b -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')

curl -H "Host: app-a.gwapi.example.com" "http://${LB_A}/"
curl -H "Host: app-b.gwapi.example.com" "http://${LB_B}/"
```

> Se o seletor de label acima não bater no seu cluster, confira o nome exato do `Service` com
> `oc get svc -n openshift-ingress` e pegue o IP manualmente — o nome padrão esperado é
> `gateway-app-a-openshift-default` / `gateway-app-b-openshift-default`.

Confirme que os dois respondem, cada um pelo seu próprio `LoadBalancer` — prova de que são
duas instâncias de verdade, não uma só compartilhada.

> **Confirmado ao vivo**: `app-a` responde `200` só via `LB_A`, `app-b` só via `LB_B`. Teste
> cruzado (`Host: app-a.gwapi.example.com` contra `LB_B`) retorna `404` — prova de isolamento
> real entre os dois `Gateway`s, não é só um LB compartilhado com hostnames diferentes.

---

## Passo 5: Comparar com o Router Clássico

```bash
oc get svc -n openshift-ingress
```

Ao lado dos dois `LoadBalancer` novos do Gateway API, você ainda vê o `router-default` (ou
equivalente) do modelo clássico — os dois modelos coexistem no mesmo cluster, sem conflito.

---

## Passo 6: Limpeza

```bash
oc delete -f 11-GatewayAPI/manifests/08-httproute-b.yaml
oc delete -f 11-GatewayAPI/manifests/07-httproute-a.yaml
oc delete -f 11-GatewayAPI/manifests/06-gateway-b.yaml
oc delete -f 11-GatewayAPI/manifests/05-gateway-a.yaml
oc delete -f 11-GatewayAPI/manifests/04-app-b.yaml
oc delete -f 11-GatewayAPI/manifests/03-app-a.yaml
oc delete namespace lab-gateway-demo
```

Deixe o `GatewayClass openshift-default` (é reutilizável por outros labs/apps futuras).

---

## Referências

- [Gateway API with OpenShift Container Platform networking — OKD docs](https://docs.okd.io/latest/networking/ingress_load_balancing/configuring_ingress_cluster_traffic/ingress-gateway-api.html)
- [Using the Gateway API on OpenShift — Simon Krenger](https://www.krenger.ch/blog/using-the-gateway-api-on-openshift/) — fonte do YAML testado usado neste lab.
- [Integrate OpenShift Gateway API with OpenShift Service Mesh — Red Hat Developer](https://developers.redhat.com/articles/2025/12/09/integrate-openshift-gateway-api-openshift-service-mesh)
- [Introducing Gateway API with OpenShift Networking — Red Hat blog](https://www.redhat.com/en/blog/introducing-gateway-api-with-openshift-networking-developer-preview)
