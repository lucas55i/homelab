output "k3s_nodes" {
  description = "Informações dos nodes K3s"
  value = {
    for idx, vm in proxmox_vm_qemu.k3s_nodes : vm.name => {
      id   = vm.id
      ip   = "${var.k3s_ip_base}.${idx + 10}"
      name = vm.name
    }
  }
}

output "docker_nodes" {
  description = "Informações dos nodes Docker"
  value = {
    for idx, vm in proxmox_vm_qemu.docker_nodes : vm.name => {
      id   = vm.id
      ip   = "${var.docker_ip_base}.${idx + 20}"
      name = vm.name
    }
  }
}

output "ansible_inventory" {
  description = "Inventário para Ansible"
  value = <<-EOT
[k3s_master]
${proxmox_vm_qemu.k3s_nodes[0].name} ansible_host=${var.k3s_ip_base}.10

[k3s_workers]
${proxmox_vm_qemu.k3s_nodes[1].name} ansible_host=${var.k3s_ip_base}.11

[docker]
${proxmox_vm_qemu.docker_nodes[0].name} ansible_host=${var.docker_ip_base}.20
${proxmox_vm_qemu.docker_nodes[1].name} ansible_host=${var.docker_ip_base}.21

[k3s:children]
k3s_master
k3s_workers

[all:vars]
ansible_user=${var.vm_user}
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOT
}
