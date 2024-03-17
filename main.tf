terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.95.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = ""
  client_id       = ""
  client_secret   = ""
  tenant_id       = ""
}

locals {
  ips = tolist([for i in range(100, 100 + var.instance_count) : cidrhost(var.subnet_cidr, i)])
}

resource "azurerm_resource_group" "test-rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "test-network" {
  depends_on = [ azurerm_resource_group.test-rg ]
  name                = var.network_name
  address_space       = [var.address_space]
  location            = azurerm_resource_group.test-rg.location
  resource_group_name = azurerm_resource_group.test-rg.name
}

resource "azurerm_subnet" "test-network-subnet" {
  depends_on = [ azurerm_virtual_network.test-network ]
  name                 = var.subnet_name
  resource_group_name  = azurerm_resource_group.test-rg.name
  virtual_network_name = azurerm_virtual_network.test-network.name
  address_prefixes     = [var.subnet_cidr]
}


# Create public IPs
resource "azurerm_public_ip" "my_terraform_public_ip" {
  depends_on = [ azurerm_subnet.test-network-subnet ]
  count               = var.instance_count
  name                = "myPublicIP-${count.index}"
  location            = azurerm_resource_group.test-rg.location
  resource_group_name = azurerm_resource_group.test-rg.name
  allocation_method   = "Dynamic"

  timeouts {
    create = "10m"  # Timeout for resource creation (10 minutes)
    update = "5m"   # Timeout for resource update (5 minutes)
    delete = "5m"   # Timeout for resource deletion (5 minutes)
  }
}

resource "azurerm_network_security_group" "test-sec-group" {
  depends_on = [ azurerm_resource_group.test-rg ]
  name                = "mySG"
  location            = azurerm_resource_group.test-rg.location
  resource_group_name = azurerm_resource_group.test-rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "nics" {
  depends_on = [ azurerm_resource_group.test-rg, azurerm_subnet.test-network-subnet, azurerm_public_ip.my_terraform_public_ip ]
  count               = var.instance_count
  name                = "test-nic-${count.index}"
  location            = azurerm_resource_group.test-rg.location
  resource_group_name = azurerm_resource_group.test-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.test-network-subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.ips[count.index]
    public_ip_address_id          = azurerm_public_ip.my_terraform_public_ip[count.index].id
  }
}

resource "azurerm_network_interface_security_group_association" "sec-grp-assoc" {
  depends_on = [ azurerm_network_security_group.test-sec-group ]
  count                     = var.instance_count
  network_interface_id      = azurerm_network_interface.nics[count.index].id
  network_security_group_id = azurerm_network_security_group.test-sec-group.id
}

resource "random_password" "vm_password" {
  count            = var.instance_count
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_linux_virtual_machine" "example" {
  
  depends_on = [azurerm_network_interface.nics, azurerm_public_ip.my_terraform_public_ip]

  count                 = var.instance_count
  name                  = "ping-vm-${count.index}"
  location              = azurerm_resource_group.test-rg.location
  resource_group_name   = azurerm_resource_group.test-rg.name
  network_interface_ids = [azurerm_network_interface.nics[count.index].id]
  size                  = var.size

  os_disk {
    name                 = "myOsDisk-${count.index}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  computer_name  = var.computer_host_name
  admin_username = var.adminuser
  admin_password = random_password.vm_password[count.index].result

  admin_ssh_key {
    username   = var.adminuser
    public_key = file("~/.ssh/id_rsa.pub")
  }

}

resource "time_sleep" "wait_60_seconds_creation" {
  depends_on = [ azurerm_linux_virtual_machine.example ]
  create_duration = "60s"
}

data "azurerm_public_ip" "my-ip" {
    count = var.instance_count
    name = azurerm_public_ip.my_terraform_public_ip[count.index].name
    resource_group_name = azurerm_linux_virtual_machine.example[count.index].resource_group_name
}

locals  {
    public_ip_address = tolist([ for i in range(var.instance_count): data.azurerm_public_ip.my-ip[i].ip_address])
}
resource "null_resource" "ping_command" {

  depends_on = [ time_sleep.wait_60_seconds_creation ]

  count = var.instance_count
  
  triggers = {
        public_ip = azurerm_public_ip.my_terraform_public_ip[count.index].ip_address
    }

  connection {
    type        = "ssh"
    user        = var.adminuser
    # host        = azurerm_public_ip.my_terraform_public_ip[count.index].ip_address
    host = local.public_ip_address[count.index]
    port        = "22"
    private_key = file("~/.ssh/id_rsa")
    timeout     = "1m"
    agent       = false
  }

  provisioner "remote-exec" {
    inline = [
      "ping -c 4 ${azurerm_linux_virtual_machine.example[(count.index + 1) % var.instance_count].private_ip_address} > /tmp/ping_output_${azurerm_linux_virtual_machine.example[count.index].name}.txt"
    ]
  }

  provisioner "local-exec" {
    command = "scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ${var.adminuser}@${local.public_ip_address[count.index]}:/tmp/ping_output_${azurerm_linux_virtual_machine.example[count.index].name}.txt ./output-folder/"
  }
}

resource "local_file" "create_file" {
    filename = "./output-folder/combined_output.txt"
    content = ""
}

resource "null_resource" "combine_files" {

  depends_on = [null_resource.ping_command, local_file.create_file]
  provisioner "local-exec" {
    command = <<-EOT
        if [ $(ls -1 ./output-folder/ping_output_*.txt 2>/dev/null | wc -l) -eq ${var.instance_count} ]; then
            cat ./output-folder/ping_output_*.txt >> ./output-folder/combined_output.txt
        else
            echo "Files does not exist."
        fi
    EOT
  }

  triggers = {
    always_run = "${timestamp()}"
  }
}

resource "time_sleep" "wait_5_seconds" {
  depends_on = [null_resource.combine_files]
  create_duration = "5s"
}

output "ping_output" {
  depends_on = [ null_resource.combine_files, time_sleep.wait_5_seconds ]
  value = fileexists("./output-folder/combined_output.txt") ? file("./output-folder/combined_output.txt") : "echo 'Hello world'"
}