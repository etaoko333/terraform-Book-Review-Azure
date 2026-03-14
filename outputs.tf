output "web_vm_public_ip" {
  value       = azurerm_public_ip.web_vm.ip_address
  description = "Web VM public IP"
}

output "load_balancer_public_ip" {
  value       = azurerm_public_ip.web_lb.ip_address
  description = "Public Load Balancer IP"
}

output "app_internal_lb_ip" {
  value       = "10.0.3.100"
  description = "Internal Load Balancer private IP"
}

output "mysql_endpoint" {
  value       = azurerm_mysql_flexible_server.main.fqdn
  description = "MySQL server endpoint"
}

output "ssh_web_vm" {
  value       = "ssh azureuser@${azurerm_public_ip.web_vm.ip_address}"
  description = "SSH command for web VM"
}

output "ssh_app_vm" {
  value       = "ssh -J azureuser@${azurerm_public_ip.web_vm.ip_address} azureuser@${azurerm_network_interface.app.private_ip_address}"
  description = "SSH command for app VM via web VM"
}

output "app_url" {
  value       = "http://${azurerm_public_ip.web_lb.ip_address}"
  description = "Book Review App URL"
}
