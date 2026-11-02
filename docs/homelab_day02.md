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

## 7. Próximos Passos

- [ ] Reconciliar a fonte de verdade: alinhar nomes/grupos/IPs entre `terraform/`, `ansible/inventory/hosts` e `site.yml`
- [ ] Reimportar as VMs para o state do Terraform (`terraform import`) ou aceitar que são gerenciadas manualmente
- [ ] Rodar `site.yml` após corrigir os grupos do inventário (`k3s`, e `docker` se ainda fizer sentido) — isso também resolve o aviso de resolução de nome (`/etc/hosts`)
