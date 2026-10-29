output "k3s_nodes" {
  description = "Informações dos nós do cluster K3s"
  value = {
    for name, vm in proxmox_vm_qemu.k3s_nodes : name => {
      id   = vm.id
      name = vm.name
      ip   = var.k3s_nodes[name].ip
      tags = vm.tags
    }
  }
}

output "ansible_inventory" {
  description = "Inventário no formato Ansible para o cluster K3s"
  value       = <<-EOT
    [k3s_master]
    luffy ansible_host=${var.k3s_nodes["luffy"].ip}

    [k3s_workers]
    zoro ansible_host=${var.k3s_nodes["zoro"].ip}
    sanji ansible_host=${var.k3s_nodes["sanji"].ip}

    [k3s:children]
    k3s_master
    k3s_workers

    [all:vars]
    ansible_user=${var.vm_user}
    ansible_ssh_common_args='-o StrictHostKeyChecking=no'
  EOT
}
