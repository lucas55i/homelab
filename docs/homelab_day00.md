# Homelab Setup — Documentação - Dia 01 | 24/05/2026

Registro completo do processo de criação da infraestrutura com Proxmox, Terraform e Ansible.

---

## 1. Criação do Template no Proxmox

### Problema inicial
O template original (`ubuntu-cloud-template`, VM 9000) foi criado sem disco de dados. O `qm config` mostrava apenas:

```
bootdisk: scsi0
ide2: local-lvm:vm-9000-cloudinit,media=cdrom
```

Sem nenhum `scsi0` definido com dados reais, as VMs clonadas subiam sem disco bootável.

### Solução: criar template a partir de VM instalada

Em vez de usar uma cloud image, foi criada uma VM manualmente com Debian via ISO, configurada com:
- Usuário `luffy` com senha
- SSH habilitado
- `qemu-guest-agent` instalado

Depois convertida em template:

```bash
qm template 100
# Saída esperada:
# Renamed "vm-100-disk-0" to "base-100-disk-0" in volume group "pve"
```

O `terraform.tfvars` foi atualizado para apontar para o novo template:

```hcl
template_name = "Debian-lab00"
```

---

## 2. Terraform — Provisionamento das VMs

### Erros encontrados

**Erro 1: disco sem `slot`**
O bloco `disk` sem o parâmetro `slot` fazia as VMs subirem sem disco.

**Erro 2: `scsihw: lsi`**
O controlador SCSI padrão (`lsi`) não consegue fazer boot com imagens modernas. A VM mostrava:
```
Boot failed: not a bootable disk
No bootable device. Retrying in 1 seconds.
```

**Erro 3: discos órfãos**
Cada `terraform apply` criava um novo disco sem remover o anterior, acumulando `unused0`, `unused1`, `unused2` na config da VM.

### Configuração final do `main.tf`

```hcl
resource "proxmox_vm_qemu" "k3s_nodes" {
  ...
  scsihw    = "virtio-scsi-pci"   # controlador correto
  boot      = "order=scsi0"       # ordem de boot explícita
  full_clone = true

  disk {
    slot    = 0
    size    = "15G"
    type    = "scsi"
    storage = "local-lvm"
    format  = "raw"
  }
  ...
}
```

### Limpeza de discos órfãos

```bash
pvesm free local-lvm:vm-100-disk-0
pvesm free local-lvm:vm-100-disk-1
pvesm free local-lvm:vm-100-disk-2
```

---

## 3. Boot travado — "Wait for Network to be Configured"

### Sintoma
```
[**] A start job is running for Wait for Network to be Configured (40s / no limit)
```

### Causa
O cloud-init não estava aplicando as configurações de rede porque o template foi criado a partir de uma instalação manual (não cloud image). As VMs pegaram IPs via DHCP em vez dos IPs estáticos definidos no Terraform.

### IPs reais das VMs (via DHCP)

| VM | IP |
|---|---|
| k3s-node-1 | 192.168.15.111 |
| k3s-node-2 | 192.168.15.89 |
| docker-node-1 | 192.168.15.121 |
| docker-node-2 | 192.168.15.43 |

O inventário do Ansible foi atualizado com esses IPs reais.

---

## 4. Ansible — Inventário e Conectividade

### Estrutura

```
ansible/
├── ansible.cfg
├── inventory/
│   └── hosts.yml
└── playbooks/
    ├── ping.yml
    └── copy-ssh-key.yml
```

### `inventory/hosts.yml`

```yaml
all:
  vars:
    ansible_user: luffy
    ansible_ssh_private_key_file: ~/.ssh/homelab
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'

  children:
    k3s:
      children:
        k3s_master:
          hosts:
            k3s-node-1:
              ansible_host: 192.168.15.111
        k3s_workers:
          hosts:
            k3s-node-2:
              ansible_host: 192.168.15.89
    docker:
      hosts:
        docker-node-1:
          ansible_host: 192.168.15.121
        docker-node-2:
          ansible_host: 192.168.15.43
```

---

## 5. Configuração de Chave SSH

### Problema
A chave `~/.ssh/homelab` tinha permissões erradas (`-rw-rw-r--`). SSH exige `600` na chave privada.

```bash
chmod 600 ~/.ssh/homelab
```

### Problema 2: chave não estava nas VMs
O template foi criado manualmente sem a chave `homelab` no `authorized_keys`. As VMs só aceitavam senha.

### Problema 3: permissões do `.ssh` incorretas
O playbook `copy-ssh-key.yml` rodou com `become: true` e criou o diretório `.ssh` com dono `root`, fazendo o SSH rejeitar a chave mesmo após copiada.

**Sintoma:**
```
cat: /home/luffy/.ssh/authorized_keys: Permissão recusada
```

### Solução: corrigir permissões via Ansible

```bash
# Corrigir dono e permissão do diretório
ansible all -b -m file -a "path=/home/luffy/.ssh owner=luffy group=luffy mode=0700 recurse=yes"

# Corrigir permissão do authorized_keys
ansible all -b -m file -a "path=/home/luffy/.ssh/authorized_keys owner=luffy group=luffy mode=0600"
```

### Playbook `copy-ssh-key.yml` (versão final)

```yaml
- name: Copiar chave SSH para todas as VMs
  hosts: all
  gather_facts: false
  become: true

  tasks:
    - name: Garantir que o diretório .ssh existe com permissões corretas
      ansible.builtin.file:
        path: /home/luffy/.ssh
        state: directory
        mode: '0700'
        owner: luffy
        group: luffy

    - name: Adicionar chave pública homelab ao authorized_keys
      ansible.posix.authorized_key:
        user: luffy
        state: present
        key: "{{ lookup('file', '~/.ssh/homelab.pub') }}"
```

> **Nota:** Para o `become` funcionar sem senha, o usuário precisa estar no sudoers sem senha:
> ```bash
> echo "luffy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/luffy
> chmod 440 /etc/sudoers.d/luffy
> ```

---

## 6. Resultado Final

Todas as 4 VMs respondendo via SSH com chave, sem senha:

```
docker-node-1  192.168.15.121  ✅  up
docker-node-2  192.168.15.43   ✅  up
k3s-node-1     192.168.15.111  ✅  up
k3s-node-2     192.168.15.89   ✅  up
```

```bash
ansible-playbook playbooks/ping.yml
# PLAY RECAP
# docker-node-1: ok=3  changed=0  unreachable=0  failed=0
# docker-node-2: ok=3  changed=0  unreachable=0  failed=0
# k3s-node-1:    ok=3  changed=0  unreachable=0  failed=0
# k3s-node-2:    ok=3  changed=0  unreachable=0  failed=0
```

---

## Próximos Passos

- [ ] Instalar Docker nos `docker_nodes` via Ansible
- [ ] Instalar k3s nos `k3s_nodes` via Ansible
- [ ] Configurar IPs estáticos nas VMs (remover dependência do DHCP)
- [ ] Adicionar chave SSH ao template para evitar o processo manual nas próximas VMs
