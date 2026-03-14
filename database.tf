# Private DNS Zone for MySQL
resource "azurerm_private_dns_zone" "mysql" {
  name                = "bookreview.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                  = "mysql-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  resource_group_name   = azurerm_resource_group.main.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

# MySQL Flexible Server
resource "azurerm_mysql_flexible_server" "main" {
  name                   = "bookreview-mysql"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  administrator_login    = "bookadmin"
  administrator_password = "Book12345678"
  backup_retention_days  = 7
  delegated_subnet_id    = azurerm_subnet.db1.id
  private_dns_zone_id    = azurerm_private_dns_zone.mysql.id
  sku_name               = "GP_Standard_D2ds_v4"
  version                = "8.0.21"
  zone                   = "1"

  depends_on = [azurerm_private_dns_zone_virtual_network_link.mysql]
}

# Create bookstore database
resource "azurerm_mysql_flexible_database" "main" {
  name                = "bookstore"
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_mysql_flexible_server.main.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}
