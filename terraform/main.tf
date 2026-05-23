terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
  }
}

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_user         = var.proxmox_user
  pm_password     = var.proxmox_password
  pm_tls_insecure = var.proxmox_tls_insecure
}

# VMs para K3s Cluster
resource "proxmox_vm_qemu" "k3s_nodes" {
  count       = 2
  name        = "k3s-node-${count.index + 1}"
  target_node = var.proxmox_node
  clone       = var.template_name
  
  # Configurações de CPU e Memória
  cores   = 2
  sockets = 1
  memory  = 2048
  
  # Configurações de Disco
  disk {
    size    = "15G"
    type    = "scsi"
    storage = var.storage_pool
  }
  
  # Configurações de Rede
  network {
    model  = "virtio"
    bridge = var.network_bridge
  }
  
  # Cloud-init
  os_type   = "cloud-init"
  ipconfig0 = "ip=${var.k3s_ip_base}.${count.index + 10}/24,gw=${var.gateway}"
  
  ciuser     = var.vm_user
  cipassword = var.vm_password
  sshkeys    = var.ssh_public_key
  
  # Iniciar automaticamente
  onboot = true
  
  tags = "k3s,kubernetes"
}

# VMs para Docker
resource "proxmox_vm_qemu" "docker_nodes" {
  count       = 2
  name        = "docker-node-${count.index + 1}"
  target_node = var.proxmox_node
  clone       = var.template_name
  
  # Configurações de CPU e Memória
  cores   = 2
  sockets = 1
  memory  = 2048
  
  # Configurações de Disco
  disk {
    size    = "10G"
    type    = "scsi"
    storage = var.storage_pool
  }
  
  # Configurações de Rede
  network {
    model  = "virtio"
    bridge = var.network_bridge
  }
  
  # Cloud-init
  os_type   = "cloud-init"
  ipconfig0 = "ip=${var.docker_ip_base}.${count.index + 20}/24,gw=${var.gateway}"
  
  ciuser     = var.vm_user
  cipassword = var.vm_password
  sshkeys    = var.ssh_public_key
  
  # Iniciar automaticamente
  onboot = true
  
  tags = "docker,containers"
}
