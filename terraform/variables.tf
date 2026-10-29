variable "proxmox_api_url" {
  description = "URL da API do Proxmox"
  type        = string
  default     = "http://192.168.15.18:8006/api2/json"
}

variable "proxmox_user" {
  description = "Usuário do Proxmox (formato: user@pam ou user@pve)"
  type        = string
}

variable "proxmox_password" {
  description = "Senha do usuário Proxmox"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Ignorar verificação de certificado SSL"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Nome do node Proxmox"
  type        = string
  default     = "pve"
}

variable "template_name" {
  description = "Nome do template de VM no Proxmox"
  type        = string
  default     = "Debian-lab00"
}

variable "storage_pool" {
  description = "Storage pool do Proxmox"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Bridge de rede do Proxmox"
  type        = string
  default     = "vmbr0"
}

variable "k3s_nodes" {
  description = "Mapa dos nós do cluster K3s (chave = nome/hostname da VM)"
  type = map(object({
    ip        = string
    cores     = number
    memory    = number
    disk_size = string
    tags      = string
  }))
  default = {
    luffy = {
      ip        = "192.168.15.10"
      cores     = 1
      memory    = 2048
      disk_size = "32G"
      tags      = "k3s,kubernetes,control-plane,linux,lab"
    }
    zoro = {
      ip        = "192.168.15.134"
      cores     = 1
      memory    = 2048
      disk_size = "32G"
      tags      = "k3s,kubernetes,worker,linux,lab"
    }
    sanji = {
      ip        = "192.168.15.3"
      cores     = 1
      memory    = 2048
      disk_size = "32G"
      tags      = "k3s,kubernetes,worker,linux,lab"
    }
  }
}

variable "gateway" {
  description = "Gateway da rede"
  type        = string
  default     = "192.168.15.1"
}

variable "vm_user" {
  description = "Usuário padrão das VMs"
  type        = string
  default     = "admin"
}

variable "vm_password" {
  description = "Senha padrão das VMs"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Chave SSH pública para acesso às VMs"
  type        = string
}
