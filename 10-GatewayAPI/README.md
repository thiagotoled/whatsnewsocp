# Exercício 12: Gateway API

Neste laboratório, você vai subir um `Gateway` — com seu próprio `Deployment` e `Service` do
tipo `LoadBalancer` — e comparar isso com o modelo clássico do Route/Router do OpenShift.

---

## Conceito Rápido

O Gateway API é a evolução **Kubernetes-nativa** do Ingress — parte do projeto upstream
`gateway-api`, não específico do OpenShift (diferente do `Route`, que é uma API só da Red Hat).
A spec não exige Istio em lugar nenhum — em Kubernetes puro você instala os CRDs na mão e
escolhe qualquer implementação (Istio, Envoy Gateway, Contour, Cilium, etc.) pra reconciliar os
objetos. No OpenShift, a API/CRDs vêm via Ingress Operator (GA desde o 4.19), e a implementação
escolhida pela Red Hat usa um `istiod` (baseado em Istio) por baixo dos panos — mas **confirmado
ao vivo que o próprio Ingress Operator já provisiona esse `istiod` sozinho** quando o primeiro
`GatewayClass` é criado, então você nunca precisa instalar ou gerenciar o OpenShift Service Mesh
Operator diretamente pra usar Gateway API aqui.

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

---

## Pré-requisitos

- Acesso de administrador de cluster (pra criar `GatewayClass`, cluster-scoped, e recursos em
  `openshift-ingress`).

---

## Passo 1: Confirmar/Criar o `GatewayClass`

```bash
oc get gatewayclass
```

Se `openshift-default` já aparecer na lista, pule a criação. Senão:

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/10-GatewayAPI/manifests/01-gatewayclass.yaml
oc get gatewayclass openshift-default -o jsonpath='{.status.conditions}' | jq .
```

Espere a condição `Accepted: "True"`.

---

## Passo 2: Subir a App de Exemplo

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/10-GatewayAPI/manifests/02-namespace.yaml
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/10-GatewayAPI/manifests/03-app.yaml
oc get pods -n lab-gateway-demo
```

Uma app simples ("Hello OpenShift") — o ponto do lab é o roteamento, não o conteúdo da
resposta.

---

## Passo 3: Criar o `Gateway`

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/10-GatewayAPI/manifests/04-gateway.yaml
```

Confirme que ele gerou seu próprio `Deployment` e `Service LoadBalancer`:

```bash
oc get deployment -n openshift-ingress | grep gateway-app
oc get svc -n openshift-ingress | grep gateway-app
```

Anote o `EXTERNAL-IP`/hostname.

---

## Passo 4: Criar o `HTTPRoute` e Testar

```bash
oc apply -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/10-GatewayAPI/manifests/05-httproute.yaml
```

Como o hostname (`app.gwapi.example.com`) não tem DNS real apontando pra ele (diferente do
`Route` clássico, que ganha um subdomínio automático em `*.apps.<seu-domínio>`), teste direto
contra o IP/hostname do `LoadBalancer`, informando o `Host` manualmente:

```bash
LB=$(oc get svc -n openshift-ingress -l gateway.networking.k8s.io/gateway-name=gateway-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')

curl -H "Host: app.gwapi.example.com" "http://${LB}/"
```

> Se o seletor de label acima não bater no seu cluster, confira o nome exato do `Service` com
> `oc get svc -n openshift-ingress` e pegue o IP manualmente — o nome padrão esperado é
> `gateway-app-openshift-default`.

---

## Passo 5: Comparar com o Router Clássico

```bash
oc get svc -n openshift-ingress
```

Ao lado do `LoadBalancer` novo do Gateway API, você ainda vê o `router-default` (ou
equivalente) do modelo clássico — os dois modelos coexistem no mesmo cluster, sem conflito.

---

## Passo 6: Limpeza

```bash
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/10-GatewayAPI/manifests/05-httproute.yaml
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/10-GatewayAPI/manifests/04-gateway.yaml
oc delete -f https://raw.githubusercontent.com/thiagotoled/whatsnewsocp/refs/heads/main/10-GatewayAPI/manifests/03-app.yaml
oc delete namespace lab-gateway-demo
```

Deixe o `GatewayClass openshift-default` (é reutilizável por outros labs/apps futuras).

---

## Referências

- [Using the Gateway API on OpenShift — Simon Krenger](https://www.krenger.ch/blog/using-the-gateway-api-on-openshift/)
- [Integrate OpenShift Gateway API with OpenShift Service Mesh — Red Hat Developer](https://developers.redhat.com/articles/2025/12/09/integrate-openshift-gateway-api-openshift-service-mesh)
- [Introducing Gateway API with OpenShift Networking — Red Hat blog](https://www.redhat.com/en/blog/introducing-gateway-api-with-openshift-networking-developer-preview)
