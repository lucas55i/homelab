# Homelab Setup — Dia 03 | 02/11/2026

Sessão de verificação de conectividade e reconciliação entre o que está documentado, o que está no código (Terraform/Ansible) e o estado real da infraestrutura.

---

## 1. Objetivo

Validar se as VMs provisionadas estão de pé e acessíveis via SSH e Ansible, e confirmar qual é a fonte de verdade correta — já que `docs`, `terraform/` e `ansible/inventory` descreviam infraestruturas divergentes.

---

## 2. Estado real verificado

As três VMs do cluster estão **up e acessíveis**. Teste feito por ping, porta SSH (22), SSH com a chave `~/.ssh/homelab` e `ansible -m ping`.

| Host (inventário) | IP | Hostname real | Ping | SSH (chave) | Ansible ping | sudo (become) |
|---|---|---|---|---|---|---|
| k8s-master | 192.168.15.10 | `luffy` | ✅ | ✅ | ✅ SUCCESS | ✅ (com senha) |
| k8s-worker-01 | 192.168.15.134 | `zoro` | ✅ | ✅ | ✅ SUCCESS | ✅ (com senha) |
| k8s-worker-02 | 192.168.15.3 | `sanji` | ✅ | ✅ | ✅ SUCCESS | ✅ (com senha) |

- SO: Debian, kernel `6.1.0-52-amd64`.
- Usuário de acesso: `luffy` com a chave `~/.ssh/homelab`.

```bash
ansible all -m ping
# k8s-master    | SUCCESS => "ping": "pong"
# k8s-worker-01 | SUCCESS => "ping": "pong"
# k8s-worker-02 | SUCCESS => "ping": "pong"
```

---

## 3. Divergências encontradas (importante)

### 3.1 A realidade bate com o Terraform, não com os docs antigos

Os IPs **estáticos** definidos em `terraform/variables.tf` (`.10` / `.134` / `.3`) são os que respondem. Os IPs **DHCP** registrados em `homelab_day00.md` / `homelab_day01.md` (`.111` / `.89` / `.121` / `.43`) **não respondem mais** (ping e SSH falharam em todos).

Os hostnames reais das VMs (`luffy`, `zoro`, `sanji`) são exatamente os nomes definidos em `terraform/main.tf` (`var.k3s_nodes`). Ou seja, a infra atual é o **cluster de 3 nós K3s do Terraform**, e a topologia de "2 K3s + 2 Docker" dos docs antigos pertence a uma iteração anterior que não existe mais.

### 3.2 O inventário versionado usa nomes/grupos desalinhados

`ansible/inventory/hosts` usa nomes `k8s-master` / `k8s-worker-01` / `k8s-worker-02` e grupos `k8s_*`, enquanto:
- `terraform/main.tf` e `outputs.tf` usam `luffy`/`zoro`/`sanji` e grupos `k3s_*`.
- `ansible/playbooks/site.yml` referencia os grupos `docker` e `k3s`, que **não existem** no inventário atual.

Consequência prática: o `site.yml` versionado não aplica o role `docker` (grupo inexistente) nem o role `k3s` (grupo `k3s` inexistente) com o inventário atual.

### 3.3 O NOPASSWD **não** está ativo nas VMs atuais

Apesar de `homelab_day01.md` registrar que o `sudoers.yml` foi aplicado, o teste mostrou que o sudo ainda exige senha nestas VMs:

```
sudo: é necessária uma senha
```

O `become` só funciona hoje porque `ansible/inventory/hosts` carrega `ansible_become_password=vocesabe`. Essas VMs são novas (uptime de ~5 min no momento do teste) e não passaram pelo `sudoers.yml`.

### 3.4 Resolução de nome local ausente

O sudo emite aviso `impossível resolver o anfitrião zoro/sanji`. O role `common` adiciona o hostname ao `/etc/hosts`, mas ele ainda não rodou nessas VMs. É cosmético por enquanto, não bloqueia a conexão.

---

## 4. Estado do Terraform

O arquivo `terraform/terraform.tfstate` está praticamente **vazio** (sem recursos gerenciados). As VMs existem no Proxmox, mas estão **fora do controle do state** — comportamento coerente com o crash do provider `telmate/proxmox` documentado no README. Qualquer `terraform plan/apply` hoje tentaria recriar tudo do zero.

---

## 5. Pendência de segurança

A senha de sudo (`ansible_become_password=vocesabe`) está em texto puro e **versionada no Git** dentro de `ansible/inventory/hosts`. Como o NOPASSWD não está ativo, a senha ainda é necessária para o Ansible operar — então não dá para simplesmente removê-la sem antes:

1. Rodar o `playbooks/sudoers.yml` para ativar o NOPASSWD de fato, **ou**
2. Migrar o segredo para **Ansible Vault**.

Depois disso, remover a linha do inventário e considerar limpar o histórico do Git (a senha já está no histórico).

---

## 6. Ações executadas nesta sessão

### 6.1 NOPASSWD ativado

Rodado `ansible-playbook playbooks/sudoers.yml`. Resultado: `changed=1`, `failed=0`
nos três hosts. Criado `/etc/sudoers.d/luffy` (mode `0440`, dono `root`),
validado via `visudo`.

```
k8s-master    : ok=1  changed=1  unreachable=0  failed=0
k8s-worker-01 : ok=1  changed=1  unreachable=0  failed=0
k8s-worker-02 : ok=1  changed=1  unreachable=0  failed=0
```

Verificação com senha vazia forçada (`-e ansible_become_password=`): os três
hosts elevaram para `root` com sucesso, confirmando o NOPASSWD.

### 6.2 Senha removida do inventário

Removida a linha `ansible_become_password=vocesabe` de
`ansible/inventory/hosts`. O `ansible all -b -m command -a "id -un"` continua
retornando `root` nos três hosts sem a senha — o inventário não depende mais do
segredo.

> **Pendência de segurança remanescente:** a senha `vocesabe` ainda está no
> **histórico do Git**. Como não é mais usada pelo Ansible, o risco é menor, mas
> se for reutilizada em outro lugar o ideal é trocá-la. Limpar o histórico
> (`git filter-repo` / BFG) reescreve hashes — avaliar conforme o repo esteja
> compartilhado ou não.

---

## 7. Validação do cluster K3s

Verificado via SSH direto nos três nós (binário, serviço systemd e estado do
cluster). O cluster está **operacional e com os 3 nós `Ready`**.

| Node | IP | Papel | Serviço ativo | Status |
|---|---|---|---|---|
| `luffy` | 192.168.15.10 | control-plane | `k3s` (server) | Ready |
| `zoro` | 192.168.15.134 | worker | `k3s-agent` | Ready |
| `sanji` | 192.168.15.3 | worker | `k3s-agent` | Ready |

- Versão: `v1.36.3+k3s1` | runtime: `containerd 2.3.2-k3s2` | Debian 12 / kernel 6.1.
- Health da API: `GET /readyz` → `ok`.
- `kube-system` saudável: `coredns`, `local-path-provisioner`, `metrics-server`
  e `traefik` todos `Running`; jobs `helm-install-traefik*` em `Completed`.

```bash
sudo k3s kubectl get nodes -o wide
# NAME    STATUS   ROLES           VERSION
# luffy   Ready    control-plane   v1.36.3+k3s1
# sanji   Ready    <none>          v1.36.3+k3s1
# zoro    Ready    <none>          v1.36.3+k3s1
```

### Observações

- **O K3s não foi instalado pelo role `k3s` desta iteração.** O `AGE` dos nós e
  dos pods é de ~85 dias (os RESTARTS recentes batem com o reboot das VMs). O
  cluster já existia e persiste entre reboots (`onboot=true` no Terraform +
  serviços systemd habilitados). Isso é coerente com o fato de o role `k3s`
  nunca ter rodado com o inventário atual (grupos `k3s`/`k3s_master`
  inexistentes — ver seção 3.2).
- **Resíduo de teste:** há 3 pods `svclb-nginx-teste-*` em `Pending` (Service
  tipo LoadBalancer de um deploy de teste antigo, provável conflito de porta
  80/443 com o Traefik). Não afeta o cluster; candidato a limpeza.

---

## 8. Reconciliação e continuidade (passos 1–4)

### 8.1 Inventário e site.yml reconciliados ✅

`ansible/inventory/hosts` foi alinhado à realidade do Terraform:

- Nomes `k8s-master`/`k8s-worker-01/02` → `luffy`/`zoro`/`sanji`.
- Grupos `k8s_*` → `k3s`/`k3s_master`/`k3s_workers` (o que o role `k3s`, o
  `site.yml` e o `outputs.tf` esperam).
- Adicionado grupo `docker` vazio (ver 8.3).

Validado: `ansible-inventory --graph` mostra a árvore correta e
`ansible k3s -b -m command -a hostname` retorna `luffy`/`zoro`/`sanji`.

> **Nota:** o `site.yml` completo **não foi executado**. O role `common` roda
> `apt upgrade dist` + mexe em swap/kernel em `hosts: all`, o que é arriscado num
> cluster K3s já em produção. Rodar só sob decisão explícita e janela adequada.

### 8.2 Deploy de teste no K3s ✅

Validado deploy funcional: o `deployment/nginx-teste` (pré-existente, criado via
`kubectl` solto) responde **HTTP 200** via ClusterIP, com pods distribuídos em
`zoro` e `sanji`. Criado manifesto versionado em `k8s/nginx-teste.yaml` e
aplicado, trocando o Service de `LoadBalancer` para `ClusterIP`. Resultado: os
pods `svclb-nginx-teste-*` em Pending (resíduo citado na seção 7) **foram
eliminados**. Rollout concluído com imagem `nginx:stable`.

### 8.3 Papel do Docker (decisão) ✅

Não há host Docker na infra atual (só o cluster K3s de 3 nós). Decisão:
**manter** o role `docker` para um host dedicado futuro, **sem** instalar Docker
nos nós K3s (que já usam containerd). O grupo `docker` fica vazio e o play
correspondente no `site.yml` vira no-op (`--list-hosts` → 0 hosts). Comentário
explicativo adicionado ao `site.yml`.

### 8.4 Terraform state (BLOQUEADO) ⚠️

Objetivo: importar as 3 VMs para o state (hoje vazio). Mapeamento confirmado via
API do Proxmox (node `proxmox`):

| Terraform key | IP | VMID |
|---|---|---|
| `luffy` | 192.168.15.10 | 102 |
| `zoro` | 192.168.15.134 | 103 |
| `sanji` | 192.168.15.3 | 101 |

O `terraform import ... proxmox/qemu/<vmid>` **falhou**: o provider
`telmate/proxmox 2.9.14` crasha ao ler o recurso:

```
panic: interface conversion: interface {} is string, not float64
  em NewConfigQemuFromApi (config_qemu.go:584)
```

É o bug conhecido do provider (citado no README) — incompatibilidade de parsing
entre a versão 2.9.x do provider e a API do Proxmox atual. Não é credencial nem
endereço. O state continua limpo (0 recursos, não corrompeu).

**Desbloqueio possível:** atualizar o provider para `telmate/proxmox ~> 3.x` ou
migrar para `bpg/proxmox` — ambos exigem reescrever o `main.tf` para a sintaxe
nova e revalidar, o que é uma mudança maior (fora do escopo deste passo).

---

## 9. Próximos Passos

- [ ] Decidir o upgrade do provider Proxmox (2.9 → 3.x ou `bpg/proxmox`) para
      destravar o import do state e parar de depender do provider que crasha
- [ ] Modernizar o role `docker`: `apt_key`/`apt_repository` estão deprecados
      (serão removidos no ansible-core 2.25) → migrar para `deb822_repository`;
      `arch=amd64` fixo → usar `dpkg --print-architecture`
- [ ] (Opcional) Rodar `site.yml`/role `common` em janela controlada para
      resolver o aviso de resolução de nome (`/etc/hosts`)
- [ ] Trocar a senha `vocesabe` (ainda no histórico do Git; usada também no
      `terraform.tfvars` local para Proxmox e VMs)
