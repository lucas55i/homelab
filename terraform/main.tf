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

# -----------------------------------------------------------------------------
# Cluster K3s (3 nós rodando em um único host Proxmox)
#
#   luffy  -> 192.168.15.10   (control-plane / master)
#   zoro   -> 192.168.15.134  (worker)
#   sanji  -> 192.168.15.3    (worker)
#
# Specs reais coletadas das VMs: 1 vCPU, 2048 MB RAM, disco de 32 GB.
# Os nós são definidos via for_each (var.k3s_nodes) porque os IPs não são
# sequenciais, então count/index não representaria a realidade.
# -----------------------------------------------------------------------------
resource "proxmox_vm_qemu" "k3s_nodes" {
  for_each = var.k3s_nodes

  name        = each.key
  target_node = var.proxmox_node
  clone       = var.template_name
  full_clone  = true

  cores   = each.value.cores
  sockets = 1
  memory  = each.value.memory

  scsihw = "virtio-scsi-pci"
  boot   = "order=scsi0"
  agent  = 1

  disk {
    slot    = 0
    size    = each.value.disk_size
    type    = "scsi"
    storage = var.storage_pool
    format  = "raw"
  }

  network {
    model  = "virtio"
    bridge = var.network_bridge
  }

  os_type   = "cloud-init"
  ipconfig0 = "ip=${each.value.ip}/24,gw=${var.gateway}"

  ciuser     = var.vm_user
  cipassword = var.vm_password
  sshkeys    = var.ssh_public_key

  onboot = true
  tags   = each.value.tags
}
