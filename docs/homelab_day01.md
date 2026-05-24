# Homelab Setup — Dia 02 | 25/05/2026

Continuação da sessão anterior. Foco em corrigir o sudo, rodar o `site.yml` e validar os roles de Docker e k3s.

---

## 1. Erro ao rodar `site.yml` — sudo com senha

### Sintoma

```
sudo: é necessária uma senha
Module result deserialization failed: No start of json char found
fatal: [docker-node-1]: FAILED!
```

O playbook `site.yml` usa `become: yes` em todos os plays, mas o usuário `luffy` não estava configurado para rodar sudo sem senha nas VMs.

### Causa

O template foi criado manualmente com o usuário `luffy` sem configuração de sudoers. O Ansible não consegue elevar privilégios sem senha ou sem `ansible_become_password` definido.

### Solução — Playbook `sudoers.yml`

Criado um playbook específico para configurar o NOPASSWD de forma segura usando `visudo` para validar o arquivo antes de aplicar:

```yaml
# playbooks/sudoers.yml
- name: Configurar sudo sem senha para luffy
  hosts: all
  gather_facts: false
  become: true

  tasks:
    - name: Adicionar luffy ao sudoers sem senha
      ansible.builtin.copy:
        dest: /etc/sudoers.d/luffy
        content: "luffy ALL=(ALL) NOPASSWD:ALL\n"
        mode: '0440'
        validate: /usr/sbin/visudo -cf %s
```

Para rodar pela primeira vez (ainda com senha), foi necessário adicionar temporariamente `ansible_become_password` no inventário:

```ini
# inventory/hosts — temporário
[all:vars]
ansible_become_password=vocesabe
```

Após rodar o playbook, a linha foi removida do inventário.

```bash
ansible-playbook playbooks/sudoers.yml
# docker-node-1: ok=1  changed=1
# docker-node-2: ok=1  changed=1
# k3s-node-1:    ok=1  changed=1
# k3s-node-2:    ok=1  changed=1
```

---

## 2. Estrutura do `site.yml`

O playbook principal orquestra três roles em sequência:

```yaml
# playbooks/site.yml
- name: Configuração inicial de todas as VMs
  hosts: all
  become: yes
  roles:
    - common

- name: Configurar Docker hosts
  hosts: docker
  become: yes
  roles:
    - docker

- name: Configurar cluster K3s
  hosts: k3s
  become: yes
  roles:
    - k3s
```

---

## 3. Role `common`

Aplicada em todas as VMs. Responsável pela configuração base do sistema:

- Atualização de pacotes (`apt upgrade`)
- Instalação de pacotes essenciais (`curl`, `wget`, `git`, `vim`, `htop`, etc.)
- Configuração de timezone (`America/Sao_Paulo`)
- Configuração de hostname
- Desabilitar swap (necessário para k3s/kubernetes)
- Carregar módulos do kernel (`overlay`, `br_netfilter`)
- Configurar parâmetros sysctl para rede de containers

---

## 4. Role `docker`

Aplicada nos hosts do grupo `docker` (docker-node-1, docker-node-2):

- Remove versões antigas do Docker
- Adiciona repositório oficial do Docker
- Instala `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`
- Adiciona `luffy` ao grupo `docker`
- Configura o daemon com log rotation e `overlay2` como storage driver
- Cria diretório `~/docker` para projetos
- Adiciona aliases úteis no `.bashrc` (`dc`, `dps`, `dimg`)

---

## 5. Role `k3s`

Aplicada nos hosts do grupo `k3s` (k3s-node-1, k3s-node-2):

**Master (k3s-node-1):**
- Instala k3s via script oficial com `--disable traefik`
- Aguarda o kubeconfig estar disponível
- Captura o token do cluster para compartilhar com os workers

**Workers (k3s-node-2):**
- Lê o token e IP do master via `hostvars`
- Instala k3s agent apontando para o master

**Todos os nodes k3s:**
- Cria `~/.kube/config` com o kubeconfig
- Adiciona alias `k='kubectl'` no `.bashrc`

---

## 6. Resultado Final

```bash
ansible-playbook playbooks/site.yml -b
# Todas as VMs: ok, sem falhas
```

| VM | Grupo | IP | Status |
|---|---|---|---|
| k3s-node-1 | k3s_master | 192.168.15.111 | ✅ |
| k3s-node-2 | k3s_workers | 192.168.15.89 | ✅ |
| docker-node-1 | docker | 192.168.15.121 | ✅ |
| docker-node-2 | docker | 192.168.15.43 | ✅ |

---

## Próximos Passos

- [ ] Configurar IPs estáticos nas VMs (remover dependência do DHCP)
- [ ] Adicionar chave SSH e sudoers ao template para evitar configuração manual nas próximas VMs
- [ ] Testar deploy de aplicação no cluster k3s
- [ ] Testar deploy de container no Docker
- [ ] Configurar monitoramento (Prometheus + Grafana)
