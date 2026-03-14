# Production-Grade 3-Tier Book Review App on Azure — Terraform Deployment Guide

Deployed and documented by **Osenat Alonge** | Senior DevOps Engineer | TOVADEL Academy

---

## What You Will Build

A fully production-ready 3-tier web application on Microsoft Azure using pure Terraform. No manual portal clicks. No manual resource creation. Everything is Infrastructure as Code.

```
Internet
    │
    ▼
Public Azure Load Balancer (port 80)
    │
    ▼
Web VM — Next.js Frontend + Nginx (public subnet)
    │
    ▼
Internal Load Balancer (10.0.3.100:3001)
    │
    ▼
App VM — Node.js Backend (private subnet)
    │
    ▼
Azure MySQL Flexible Server (private subnet)
```

---

## Architecture Overview

| Tier | Component | Subnet | Access |
|------|-----------|--------|--------|
| Web | Next.js + Nginx on Ubuntu VM | 10.0.1.0/24 (public) | Public via Load Balancer |
| App | Node.js backend on Ubuntu VM | 10.0.3.0/24 (private) | Internal only |
| DB | Azure MySQL Flexible Server | 10.0.5.0/24 (private) | App tier only |

---

## Prerequisites

Before you start make sure you have the following installed and configured:

```bash
# Check Azure CLI
az --version
az login

# Check Terraform
terraform -v

# Check Git
git --version

# Verify Azure subscription
az account show
```

---

## Project Structure

```
terraform-bookreview-azure/
├── main.tf           # Provider + VNet + 6 Subnets + NAT Gateway
├── security.tf       # NSGs for Web, App and DB tiers
├── loadbalancer.tf   # Public Load Balancer + Internal Load Balancer
├── vm.tf             # Web VM + App VM
├── database.tf       # MySQL Flexible Server + Private DNS
├── outputs.tf        # All output values
└── .gitignore        # Protects sensitive files
```

---

## Step 1 — Create the Project Directory

```bash
mkdir terraform-bookreview-azure
cd terraform-bookreview-azure
```

---

## Step 2 — Create main.tf

This file contains the Azure provider, VNet, all 6 subnets and the NAT Gateway for private subnet internet access.

```bash
cat > main.tf << 'EOF'
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "bookreview-rg"
  location = "canadacentral"
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "bookreview-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Web Subnet 1 (Public)
resource "azurerm_subnet" "web1" {
  name                 = "web-subnet-1"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Web Subnet 2 (Public)
resource "azurerm_subnet" "web2" {
  name                 = "web-subnet-2"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

# App Subnet 1 (Private)
resource "azurerm_subnet" "app1" {
  name                 = "app-subnet-1"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.3.0/24"]
}

# App Subnet 2 (Private)
resource "azurerm_subnet" "app2" {
  name                 = "app-subnet-2"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.4.0/24"]
}

# DB Subnet 1 (Private — delegated to MySQL)
resource "azurerm_subnet" "db1" {
  name                 = "db-subnet-1"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.5.0/24"]
  delegation {
    name = "mysql-delegation"
    service_delegation {
      name    = "Microsoft.DBforMySQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# DB Subnet 2 (Private)
resource "azurerm_subnet" "db2" {
  name                 = "db-subnet-2"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.6.0/24"]
}

# Public IP for NAT Gateway
resource "azurerm_public_ip" "nat" {
  name                = "nat-gateway-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# NAT Gateway
resource "azurerm_nat_gateway" "main" {
  name                = "bookreview-nat"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard"
}

# Associate Public IP with NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# Associate NAT Gateway with App Subnet
resource "azurerm_subnet_nat_gateway_association" "app" {
  subnet_id      = azurerm_subnet.app1.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}
EOF
```

---

## Step 3 — Create security.tf

This file creates NSGs for each tier with strict ingress rules.

```bash
cat > security.tf << 'EOF'
# Web NSG
resource "azurerm_network_security_group" "web" {
  name                = "web-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "HTTP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# App NSG
resource "azurerm_network_security_group" "app" {
  name                = "app-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AppPort"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3001"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "SSH"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }
}

# DB NSG
resource "azurerm_network_security_group" "db" {
  name                = "db-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "MySQL"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "10.0.3.0/24"
    destination_address_prefix = "*"
  }
}

# NSG Associations
resource "azurerm_subnet_network_security_group_association" "web1" {
  subnet_id                 = azurerm_subnet.web1.id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_subnet_network_security_group_association" "app1" {
  subnet_id                 = azurerm_subnet.app1.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "db1" {
  subnet_id                 = azurerm_subnet.db1.id
  network_security_group_id = azurerm_network_security_group.db.id
}
EOF
```

---

## Step 4 — Create loadbalancer.tf

This file creates the public load balancer for the web tier and internal load balancer for the app tier.

```bash
cat > loadbalancer.tf << 'EOF'
# Public IP for Web LB
resource "azurerm_public_ip" "web_lb" {
  name                = "web-lb-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Public Load Balancer
resource "azurerm_lb" "web" {
  name                = "web-public-lb"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "web-frontend"
    public_ip_address_id = azurerm_public_ip.web_lb.id
  }
}

resource "azurerm_lb_backend_address_pool" "web" {
  loadbalancer_id = azurerm_lb.web.id
  name            = "web-backend-pool"
}

resource "azurerm_lb_probe" "web" {
  loadbalancer_id = azurerm_lb.web.id
  name            = "web-health-probe"
  port            = 80
}

resource "azurerm_lb_rule" "web" {
  loadbalancer_id                = azurerm_lb.web.id
  name                           = "web-lb-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "web-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web.id]
  probe_id                       = azurerm_lb_probe.web.id
}

# Internal Load Balancer for App Tier
resource "azurerm_lb" "app" {
  name                = "app-internal-lb"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "app-frontend"
    subnet_id                     = azurerm_subnet.app1.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.3.100"
  }
}

resource "azurerm_lb_backend_address_pool" "app" {
  loadbalancer_id = azurerm_lb.app.id
  name            = "app-backend-pool"
}

resource "azurerm_lb_probe" "app" {
  loadbalancer_id = azurerm_lb.app.id
  name            = "app-health-probe"
  port            = 3001
}

resource "azurerm_lb_rule" "app" {
  loadbalancer_id                = azurerm_lb.app.id
  name                           = "app-lb-rule"
  protocol                       = "Tcp"
  frontend_port                  = 3001
  backend_port                   = 3001
  frontend_ip_configuration_name = "app-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.app.id]
  probe_id                       = azurerm_lb_probe.app.id
}
EOF
```

---

## Step 5 — Create vm.tf

This file creates the Web VM with a public IP and the App VM with no public IP.

```bash
cat > vm.tf << 'EOF'
# Web VM Public IP
resource "azurerm_public_ip" "web_vm" {
  name                = "web-vm-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Web VM NIC
resource "azurerm_network_interface" "web" {
  name                = "web-vm-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "web-ip-config"
    subnet_id                     = azurerm_subnet.web1.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.web_vm.id
  }
}

# Add Web VM NIC to LB Backend Pool
resource "azurerm_network_interface_backend_address_pool_association" "web" {
  network_interface_id    = azurerm_network_interface.web.id
  ip_configuration_name   = "web-ip-config"
  backend_address_pool_id = azurerm_lb_backend_address_pool.web.id
}

# Web VM
resource "azurerm_linux_virtual_machine" "web" {
  name                            = "web-vm"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = "Standard_D2s_v3"
  admin_username                  = "azureuser"
  admin_password                  = "Azure@12345678"
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.web.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }
}

# App VM NIC (No Public IP)
resource "azurerm_network_interface" "app" {
  name                = "app-vm-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "app-ip-config"
    subnet_id                     = azurerm_subnet.app1.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Add App VM NIC to Internal LB Backend Pool
resource "azurerm_network_interface_backend_address_pool_association" "app" {
  network_interface_id    = azurerm_network_interface.app.id
  ip_configuration_name   = "app-ip-config"
  backend_address_pool_id = azurerm_lb_backend_address_pool.app.id
}

# App VM
resource "azurerm_linux_virtual_machine" "app" {
  name                            = "app-vm"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = "Standard_D2s_v3"
  admin_username                  = "azureuser"
  admin_password                  = "Azure@12345678"
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.app.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }
}
EOF
```

---

## Step 6 — Create database.tf

This file provisions the MySQL Flexible Server with private DNS and VNet integration.

```bash
cat > database.tf << 'EOF'
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
EOF
```

---

## Step 7 — Create outputs.tf

```bash
cat > outputs.tf << 'EOF'
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
  description = "SSH command for app VM via web VM jump host"
}

output "app_url" {
  value       = "http://${azurerm_public_ip.web_lb.ip_address}"
  description = "Book Review App URL"
}
EOF
```

---

## Step 8 — Create .gitignore

```bash
cat > .gitignore << 'EOF'
*.tfstate
*.tfstate.backup
*.tfstate.lock.info
tfplan
*.tfplan
.terraform/
.terraform.lock.hcl
crash.log
*.tfvars
*.tfvars.json
.env
.env.local
*.pem
*.key
.DS_Store
*.log
EOF
```

---

## Step 9 — Run Terraform Pipeline

```bash
# Initialise
terraform init

# Validate
terraform validate

# Plan
terraform plan

# Apply
terraform apply
```

Type `yes` when prompted. MySQL takes 5-10 minutes to provision.

---

## Step 10 — Deploy Frontend on Web VM

```bash
# SSH into Web VM
ssh azureuser@<web-vm-public-ip>
# Password: Azure@12345678

# Upgrade Node.js to v18
sudo apt remove -y nodejs npm
sudo apt autoremove -y
sudo dpkg --purge nodejs
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs git nginx
node -v

# Clone repo
git clone https://github.com/pravinmishraaws/book-review-app.git
cd book-review-app/frontend

# Create environment file
cat > .env.local << 'ENVEOF'
NEXT_PUBLIC_API_URL=http://<load-balancer-public-ip>
ENVEOF

# Install and build
npm install
npm run build

# Start with PM2
sudo npm install -g pm2
pm2 start npm --name frontend -- start
pm2 save

# Configure Nginx
sudo tee /etc/nginx/sites-available/default << 'NGINXEOF'
server {
    listen 80;
    server_name _;

    location /api {
        proxy_pass http://10.0.3.100:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
NGINXEOF

sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx
```

---

## Step 11 — Deploy Backend on App VM

```bash
# Open new terminal and SSH via jump host
ssh -J azureuser@<web-vm-public-ip> azureuser@10.0.3.4
# Password: Azure@12345678

# Upgrade Node.js to v18
sudo apt update
sudo apt remove -y nodejs npm
sudo apt autoremove -y
sudo dpkg --purge nodejs
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs git
node -v

# Clone repo
git clone https://github.com/pravinmishraaws/book-review-app.git
cd book-review-app/backend

# Create environment file using Python to avoid special character issues
python3 << 'PYEOF'
content = """DB_HOST=bookreview-mysql.mysql.database.azure.com
DB_USER=bookadmin
DB_PASS=Book12345678
DB_NAME=bookstore
DB_PORT=3306
JWT_SECRET=bookreview_secret_key
PORT=3001
ALLOWED_ORIGINS=http://<load-balancer-ip>,http://<web-vm-ip>
"""
with open('.env', 'w') as f:
    f.write(content)
print('Done')
PYEOF

# Install and start
npm install
sudo npm install -g pm2
pm2 start src/server.js --name backend
pm2 save
pm2 status
```

---

## Step 12 — Verify Deployment

Open in browser:
```
http://<load-balancer-public-ip>
```

You should see the Book Review App with full functionality:
- Home page loads
- User registration and login works
- Books display correctly
- Reviews can be submitted

---

## Step 13 — Push to GitHub

```bash
git init
git remote add origin https://github.com/<your-username>/terraform-bookreview-azure.git
git add .
git status
git commit -m "Production 3-tier Book Review App on Azure with Terraform"
git push -u origin main
```

---

## Step 14 — Destroy Resources

Always destroy after testing to avoid unnecessary costs:

```bash
terraform destroy --auto-approve
```

---

## Common Issues and Fixes

### Issue 1 — MySQL Zone Cannot Be Changed
Azure MySQL Flexible Server zone is immutable after creation.

**Fix:**
```bash
terraform destroy \
  -target=azurerm_mysql_flexible_database.main \
  -target=azurerm_mysql_flexible_server.main \
  -target=azurerm_private_dns_zone_virtual_network_link.mysql \
  -target=azurerm_private_dns_zone.mysql
terraform apply
```

### Issue 2 — App VM Has No Internet Access
The App VM is in a private subnet by design. Without a NAT Gateway it cannot reach the internet to install packages.

**Fix:** The NAT Gateway in main.tf handles this. Make sure it is applied before trying to install packages on the App VM.

### Issue 3 — Node.js v10 Too Old
Azure Ubuntu VMs come with Node.js v10 by default. The application requires Node 18.

**Fix:**
```bash
sudo apt remove -y nodejs npm
sudo apt autoremove -y
sudo dpkg --purge nodejs
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
```

### Issue 4 — 502 Bad Gateway
Nginx cannot reach the frontend.

**Fix:** Make sure PM2 is running the frontend on port 3000:
```bash
pm2 status
pm2 restart frontend
```

### Issue 5 — SSH Host Key Changed Warning
Happens when you destroy and recreate VMs with the same IP.

**Fix:**
```bash
ssh-keygen -f "/home/<user>/.ssh/known_hosts" -R "<ip-address>"
```

---

## Tech Stack

| Tool | Purpose |
|------|---------|
| Terraform | Infrastructure as Code |
| Azure VNet | Network isolation |
| Azure Load Balancer | Public + Internal traffic routing |
| Azure MySQL Flexible Server | Managed database |
| NAT Gateway | Private subnet internet access |
| Ubuntu 20.04 | VM operating system |
| Next.js 15 | Frontend framework |
| Node.js 18 | Backend runtime |
| Nginx | Reverse proxy |
| PM2 | Process manager |

---

## Author

**Osenat Alonge**
Senior DevOps Engineer | Founder of TOVADEL Academy

LinkedIn: linkedin.com/in/osenat-alonge-84379124b
GitHub: github.com/etaoko333
TOVADEL Academy: tovadelacademy.co.uk

---

## Acknowledgements

This project was completed as part of the DevOps Micro Internship (DMI) Cohort-2 organised by Pravin Mishra.

Join DMI free: https://lnkd.in/dzJGHptZ
