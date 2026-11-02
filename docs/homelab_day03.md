# Homelab Setup — Dia 04 | 02/11/2026

> Nota de numeração: este é o 4º arquivo da série (`homelab_day03.md`). Os
> títulos dos diários estão deslocados em +1 em relação ao nome do arquivo
> (`day00.md` = "Dia 01", `day02.md` = "Dia 03", etc.). Mantido o padrão.

Observabilidade do cluster K3s com **Prometheus + Grafana**, instalados via Helm
(`kube-prometheus-stack`, perfil enxuto). Inclui o setup de acesso remoto ao
cluster pela máquina local e um exercício de `ServiceMonitor` feito à mão.

---

## 1. Objetivo

- Subir observabilidade no K3s usando o chart `kube-prometheus-stack`.
- Perfil **enxuto** por causa dos nós de 2 GB: Alertmanager desligado, retenção
  curta, recursos reduzidos, componentes de control-plane do k3s desligados.
- Tudo versionado em `k8s/monitoring/`.
- Aprender o mecanismo de descoberta de alvos escrevendo um `ServiceMonitor`.

## 2. Resultado final

| Componente | Status |
|---|---|
| Prometheus (`prometheus-...-prometheus-0`) | ✅ 2/2 Running |
| Grafana (`monitoring-grafana-...`) | ✅ 3/3 Running |
| kube-state-metrics | ✅ 1/1 Running |
| node-exporter (DaemonSet, 1 por nó) | ✅ 3/3 Running |
| Prometheus Operator | ✅ 1/1 Running |
| ServiceMonitor `nginx-teste` | ✅ descoberto (DOWN 404, esperado) |

- Chart: `kube-prometheus-stack` **92.17.0** (app `v0.94.2`).
- StorageClass usada: `local-path` (default do cluster), com PVCs.
- Grafana acessível via `port-forward` → `http://localhost:3000` (admin).

---

## 3. Arquivos criados

```
k8s/monitoring/
├── values.yaml                       # overrides do chart (perfil enxuto)
└── servicemonitor-nginx-teste.yaml   # exercício de ServiceMonitor
```

Instalação (resumo):

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --version 92.17.0 \
  -f k8s/monitoring/values.yaml
```

---

## 4. Problemas encontrados e soluções

Formato: **Sintoma → Causa → Solução**. Esta foi a parte mais trabalhosa do dia;
quase tudo girou em torno de acesso ao cluster a partir do macOS.

### 4.1 `kubectl` não conecta: `no route to host` na porta 6443

**Sintoma**
```
dial tcp 192.168.15.10:6443: connect: no route to host
```
O `kubectl`/`helm` falhavam instantaneamente. Porém:
- `nc -z 192.168.15.10 6443` → **conectava**.
- `curl -k https://192.168.15.10:6443/healthz` → respondia **HTTP 401** (= API viva).
- `ping`, SSH (porta 22) e a API consultada de outra máquina na mesma rede → OK.

**Causa**
Problema específico dos binários Go (`kubectl`/`helm`) no macOS desta máquina ao
falar com a rede local. `curl`/`nc` conectavam; o `kubectl` não — no mesmo
instante, sem proxy configurado (`env | grep -i proxy` vazio) e com uma única
interface na sub-rede. A causa exata (cache de rota/ARP para binários Go) não foi
isolada, mas foi **contornada** por túnel SSH.

**Solução — túnel SSH**
Em vez de depender da rota direta, encaminhar `6443` via SSH (que funciona 100%):

```bash
# kubeconfig do túnel, apontando para 127.0.0.1:6443
ssh -i ~/.ssh/homelab luffy@192.168.15.10 'sudo cat /etc/rancher/k3s/k3s.yaml' \
  | sed -E 's#https://127\.0\.0\.1:[0-9]+#https://127.0.0.1:6443#' \
  > ~/.kube/homelab-tunnel.yaml
chmod 600 ~/.kube/homelab-tunnel.yaml

# túnel (deixar a aba aberta); flags keepalive para estabilidade
ssh -i ~/.ssh/homelab -N -L 6443:127.0.0.1:6443 \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
  luffy@192.168.15.10

# na aba de trabalho
export KUBECONFIG=~/.kube/homelab-tunnel.yaml
kubectl get nodes   # 3 nós Ready
```

O cert do k3s já é válido para `127.0.0.1`, então não há erro de TLS.

### 4.2 Túnel quebrado com porta errada (`59562`)

**Sintoma**
```
dial tcp 127.0.0.1:59562: connect: connection refused
channel 2: open failed: connect failed: Connection refused
```

**Causa**
O `~/.kube/homelab-tunnel.yaml` acabou com `server: https://127.0.0.1:59562`
(porta de outro contexto — havia um kubeconfig de `kind` na máquina, que usa
portas altas aleatórias). Além disso, em algumas abas o `KUBECONFIG` **não**
estava exportado, então o `kubectl` caía no `~/.kube/config` default (o do kind).

**Solução**
- Regenerar o kubeconfig do túnel forçando a porta `6443` (o `sed` acima casa
  qualquer porta e normaliza para 6443).
- Exportar `KUBECONFIG=~/.kube/homelab-tunnel.yaml` em **toda** aba de trabalho.
- Confirmar sempre: `kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'`
  deve dar `https://127.0.0.1:6443`.

> Lição: ter o kubeconfig default apontando para outro cluster (`kind`) é uma
> fonte silenciosa de confusão. Sempre confirmar o `server` antes de debugar rede.

### 4.3 `sudo` do macOS recusando a senha

**Sintoma**: `sudo: 3 incorrect password attempts` ao tentar `sudo arp -d`.

**Causa**: o `sudo` no macOS usa a **senha de login do usuário** (não existe senha
de "root" habilitada por padrão). A senha foi digitada errada; o usuário É admin
(confirmado via `id -Gn` mostrando `admin` e `dscl . -read /Groups/admin`).

**Solução**: nenhum `sudo` foi necessário. A limpeza de rota/ARP virou irrelevante
assim que o túnel SSH passou a ser usado.

### 4.4 Grafana em `CrashLoopBackOff` / reiniciando (`2/3`)

**Sintoma**
```
Liveness probe failed: Get "http://.../api/health": connect: connection refused
Container grafana failed liveness probe, will be restarted
Last State: Terminated / Reason: Error / Exit Code: 1
```
O pod oscilava entre `2/3 Running` e restart.

**Causa**
**Não** era OOM (o restart veio como `Error exitCode=1`, não `OOMKilled`). Os logs
mostravam o Grafana 13 (distroless) iniciando normalmente, porém **devagar**
(apiserver interno, migrations, índice de busca bleve) em hardware modesto + disco
`local-path`. A **liveness probe** padrão do chart matava o pod antes de ele abrir
a porta 3000 → loop de restart.

**Solução** (em `k8s/monitoring/values.yaml`, bloco `grafana`)
- Afrouxar as probes: `livenessProbe.initialDelaySeconds: 120`, `failureThreshold: 10`.
- Dar folga de memória: limite `256Mi` → `384Mi` (o boot era o gargalo, não OOM).
- Aplicar com `helm upgrade` (rolling update: sobe o pod novo, depois mata o velho).

```bash
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --version 92.17.0 -f k8s/monitoring/values.yaml
```

> Detalhe do rolling update: durante o upgrade apareceu um `OOMKilled`/`Error` —
> era o **pod antigo sendo terminado**, não o novo. O pod novo nasceu `3/3`
> saudável e só então o antigo foi removido.

---

## 5. Exercício: ServiceMonitor na mão

Objetivo: entender como o Prometheus (via Operator) descobre alvos. Criado
`k8s/monitoring/servicemonitor-nginx-teste.yaml` apontando para o
`deployment/nginx-teste` (default), que **não** expõe `/metrics`.

Os 3 encaixes que fazem um ServiceMonitor funcionar (todos confirmados via CLI):

| Campo | Precisa casar com | Valor |
|---|---|---|
| `spec.selector.matchLabels` | label do Service | `app: nginx-teste` |
| `spec.endpoints[].port` | **nome** da porta (não o número) | `http` |
| `metadata.labels.release` | `serviceMonitorSelector` do Prometheus | `monitoring` |

Verificações usadas:
```bash
kubectl get svc nginx-teste -n default --show-labels
kubectl get svc nginx-teste -n default -o jsonpath='{.spec.ports}'
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.serviceMonitorSelector}'
# -> {"matchLabels":{"release":"monitoring"}}
```

### Resultado no Prometheus (Status → Targets)
```
serviceMonitor/monitoring/nginx-teste/0        0/2 up
  http://10.42.1.8:80/metrics    job="nginx-teste"   DOWN
  Error scraping target: server returned HTTP status 404 Not Found
```

**Isso é sucesso, não falha.** O `404` prova toda a cadeia: Operator leu o
ServiceMonitor → configurou o Prometheus → ele achou os 2 pods do nginx →
conectou na porta `http` → fez `GET /metrics`. O alvo ficou DOWN só porque o
nginx não tem endpoint de métricas.

> Insight central: o Prometheus **apenas coleta** métricas expostas pelo alvo.
> UP vs DOWN aqui é só isto — ter ou não um `/metrics`. Para ficar UP, o alvo
> precisaria exportar métricas (ex: sidecar `nginx-prometheus-exporter`).

---

## 6. Como acessar (resumo operacional)

```bash
# 1) túnel SSH (aba dedicada, deixar aberta)
ssh -i ~/.ssh/homelab -N -L 6443:127.0.0.1:6443 \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 luffy@192.168.15.10

# 2) kubeconfig (em TODA aba de trabalho)
export KUBECONFIG=~/.kube/homelab-tunnel.yaml

# 3) Grafana
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
#    -> http://localhost:3000  (user admin)

# 4) Prometheus
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
#    -> http://localhost:9090  (Status -> Targets)
```

---

## 7. Pendências / Próximos passos

- [ ] **Senha do Grafana em texto puro** no `values.yaml` (`vocesabe`). Antes de
      commitar: mover para um Secret ou passar via `--set`/`--values` fora do Git.
      (Mesma senha já exposta no histórico — ver day02.)
- [ ] Bônus: trocar o nginx por imagem com `/metrics` e ver o target ficar **UP**.
- [ ] Ligar Alertmanager quando for estudar alertas (hoje desligado).
- [ ] Automatizar o túnel SSH (função no `.zshrc` ou `ssh_config`) para não
      reconstruir à mão a cada sessão.
- [ ] Avaliar expor Grafana via Ingress/Traefik em vez de `port-forward`.
- [ ] Commitar `k8s/monitoring/` (após tratar a senha do Grafana).
