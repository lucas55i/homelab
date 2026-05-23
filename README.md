# Homelab Infrastructure

Infraestrutura como código para homelab com Proxmox, K3s e Docker.

## ⚠️ Aviso Importante

Este projeto foi testado em ambiente real e **funciona**, mas você encontrará alguns problemas conhecidos:

1. **Provider Proxmox crashará** - mas as VMs são criadas mesmo assim
2. **VMs precisam ser iniciadas manualmente** após o crash
3. **Cloud-init demora 3-5 minutos** - seja paciente
4. **Nome do node Proxmox** pode não ser "pve" - verifique antes

**Não se preocupe!** Todos esses problemas têm soluções documentadas em `docs/TROUBLESHOOTING.md`.

## Estrutura

```
.
├── terraform/          # Provisionamento de VMs no Proxmox
├── ansible/           # Configuração e setup das VMs
└── docs/             # Documentação adicional
```

## Componentes

- **Proxmox**: Hypervisor (192.168.15.18:8006)
- **K3s Cluster**: 2 VMs para Kubernetes leve
- **Docker Hosts**: 2 VMs para containers Docker

## Pré-requisitos

1. **Terraform** >= 1.0
2. **Ansible** >= 2.9
3. **Proxmox** VE instalado e acessível
4. **Chave SSH** configurada
5. **Paciência** - o processo leva ~15-20 minutos

