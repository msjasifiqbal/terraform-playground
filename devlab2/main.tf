terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0.2"
    }
  }
  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

data "azurerm_resource_group" "rg" {
  name = "AsifRG"
}

//declaring vaiables for vnet and subnet
variable "vnet_details" {
  description = "Details for the virtual networks to be created"
  type = map(object({
    address_space = list(string)
    subnets       = list(string)
  }))

  default = {
    vnet1 = {
      address_space = ["10.0.0.0/16"]
      subnets       = ["subnet1", "subnet2"]
    },
    vnet2 = {
      address_space = ["10.1.0.0/16"]
      subnets       = ["subnet1", "subnet2"]
    }
  }
}

//used local variable with flatten to generate the values
locals {
  subnet_details = flatten([
    for vnet_key, vnet_value in var.vnet_details : [
      for subnet in vnet_value.subnets : {
        vnet_key = vnet_key
        subnet_name   = subnet
      }
    ]
  ])
}

resource "azurerm_virtual_network" "vnet" {
  for_each = var.vnet_details

  name                = each.key
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = each.value.address_space
}

resource "azurerm_subnet" "subnet" {
  for_each = { for subnet in local.subnet_details : "${subnet.vnet_key}-${subnet.subnet_name}" => subnet }

  name                 = each.value.subnet_name
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet[each.value.vnet_key].name
  address_prefixes     = [cidrsubnet(azurerm_virtual_network.vnet[each.value.vnet_key].address_space[0], 8, index(var.vnet_details[each.value.vnet_key].subnets, each.value.subnet_name))]
}


resource "azurerm_network_security_group" "nsg" {
  for_each = { for subnet in local.subnet_details : "${subnet.vnet_key}-${subnet.subnet_name}" => subnet }

  name                = "${each.value.subnet_name}-nsg"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
}

resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  for_each = { for subnet in local.subnet_details : "${subnet.vnet_key}-${subnet.subnet_name}" => subnet }

  subnet_id                 = azurerm_subnet.subnet[each.key].id
  network_security_group_id = azurerm_network_security_group.nsg[each.key].id
}


variable "rules_file" {
  description = "The path to the CSV file containing the rules"
  type        = string
  default     = "nsgrules.csv"
}

locals {
  rules_csv = csvdecode(file(var.rules_file))
  nsg_name = { for subnet in local.subnet_details : "${subnet.vnet_key}-${subnet.subnet_name}" => {
    name = "${subnet.vnet_key}-${subnet.subnet_name}"
  } }
}

resource "azurerm_network_security_group" "this" {
  for_each = local.nsg_name

  name                = each.value.name
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  dynamic "security_rule" {
    for_each = { for rule in local.rules_csv : rule.name => rule }
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = security_rule.value.source_port_range
      destination_port_range     = security_rule.value.destination_port_range
      source_address_prefix      = security_rule.value.source_address_prefix
      destination_address_prefix = security_rule.value.destination_address_prefix
    }
  }
}