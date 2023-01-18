locals {
  target_resource_group  = format("%s-%s-%s-%03d", var.resource_group_prefix, var.purpose, var.environment_name, var.instance_id)
  target_storage_account = format("%s%s%s%03d", var.storage_account_prefix, var.purpose, var.environment_name, var.instance_id)
}
resource "azurerm_resource_group" "vm_rg" {
  name     = local.target_resource_group
  location = "West Europe"
}

resource "azurerm_virtual_network" "v_net" {
  name                = format("%s-network", var.purpose)
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.vm_rg.location
  resource_group_name = azurerm_resource_group.vm_rg.name

  tags = {
    purpose = var.purpose
  }
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.vm_rg.name
  virtual_network_name = azurerm_virtual_network.v_net.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "public_ip" {
  name                = "PublicIp1"
  resource_group_name = azurerm_resource_group.vm_rg.name
  location            = azurerm_resource_group.vm_rg.location
  allocation_method   = "Dynamic"
}

resource "azurerm_network_security_group" "nsg" {
  name                = "NetworkSecurityGroup1"
  location            = azurerm_resource_group.vm_rg.location
  resource_group_name = azurerm_resource_group.vm_rg.name
}

resource "azurerm_network_security_rule" "network_security_rule" {
  name                        = "allow22"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "VirtualNetwork"
  resource_group_name         = azurerm_resource_group.vm_rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}
resource "azurerm_network_interface" "main" {
  name                = format("%s-nic", var.purpose) #"tfvm-nic"
  location            = azurerm_resource_group.vm_rg.location
  resource_group_name = azurerm_resource_group.vm_rg.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "nic_nsg_association" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "my_storage_account" {
  name                     = local.target_storage_account
  location                 = azurerm_resource_group.vm_rg.location
  resource_group_name      = azurerm_resource_group.vm_rg.name
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Create (and display) an SSH key
resource "tls_private_key" "vm_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "az_lin_vm" {
  name                  = format("%s-%s-%s-%s", var.cloud_service_provider, var.operating_system, var.purpose, var.environment_name) #"az-tfvm-sbx"
  location              = azurerm_resource_group.vm_rg.location
  resource_group_name   = azurerm_resource_group.vm_rg.name
  network_interface_ids = [azurerm_network_interface.main.id]
  size                  = "Standard_A2_v2"


  # Uncomment this line to delete the OS disk automatically when deleting the VM
  # delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  # delete_data_disks_on_termination = true

  os_disk {
    name                 = "myOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name                   = "myvm"
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.vm_ssh.public_key_openssh
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.my_storage_account.primary_blob_endpoint
  }

  tags = {
    os = "linux"
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "vm_shutdown_schedule" {
  virtual_machine_id = azurerm_linux_virtual_machine.az_lin_vm.id
  location           = azurerm_resource_group.vm_rg.location
  enabled            = true

  daily_recurrence_time = "1700"
  timezone              = "Greenwich Standard Time"


  notification_settings {
    enabled = false

  }
}