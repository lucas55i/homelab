output "k8s_master" {
  description = "Informações dos nodes K3s"
  value = {
    for idx, vm in proxmox_vm_qemu.k8s_master : vm.name => {
      id   = vm.id
      ip   = "${var.k8s_ip_base}.${idx + 10}"
      name = vm.name
    }
  }
}

# output "docker_nodes" {
#   description = "Informações dos nodes Docker"
#   value = {
#     for idx, vm in proxmox_vm_qemu.docker_nodes : vm.name => {
#       id   = vm.id
#       ip   = "${var.docker_ip_base}.${idx + 20}"
#       name = vm.name
#     }
#   }
# }

output "ansible_inventory" {
  description = "Inventário para Ansible"
  value = <<-EOT
        [k8s_master]
        ${proxmox_vm_qemu.k8s_master[0].name} ansible_host=${var.k8s_ip_base}.10

        [k8s_workers]
        ${proxmox_vm_qemu.k8s_worker01[0].name} ansible_host=${var.k8s_ip_base}.11
        ${proxmox_vm_qemu.k8s_worker02[0].name} ansible_host=${var.k8s_ip_base}.12


        [k8s:children]
        k8s_master
        k8s_workers

        [all:vars]
        ansible_user=${var.vm_user}
        ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOT
}
