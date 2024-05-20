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

data "azurerm_resource_group" "exercise1" {
  name = "AsifRG-TF"
}


variable "vnet_details" {
  description = "Details of the VNETs and their subnets"
  type = map(object({
    address_space = list(string)
    subnets = list(object({
      name    = string
      newbits = number
      netnum  = number
    }))
  }))

  default = {
    vnet1 = {
      address_space = ["10.1.0.0/16"]
      subnets = [
        { name = "Web", newbits = 8, netnum = 1 },
        { name = "App", newbits = 8, netnum = 2 }
      ]
    }
    vnet2 = {
      address_space = ["10.2.0.0/16"]
      subnets = [
        { name = "Web", newbits = 8, netnum = 1 },
        { name = "DB", newbits = 8, netnum = 2 }
      ]
    }
  }
}


resource "azurerm_virtual_network" "vnet" {
  for_each = var.vnet_details

  name                = each.key
  resource_group_name = data.azurerm_resource_group.exercise1.name
  location            = data.azurerm_resource_group.exercise1.location
  address_space       = each.value.address_space
}

locals {
  flat_subnets = flatten([
    for vnet, details in var.vnet_details : [
      for subnet in details.subnets : {
        vnet_name   = vnet
        subnet_name = subnet.name
        newbits     = subnet.newbits
        netnum      = subnet.netnum
      }
    ]
  ])
}

resource "azurerm_subnet" "subnet" {
  for_each = { for subnet in local.flat_subnets : "${subnet.vnet_name}-${subnet.subnet_name}" => subnet }

  name                 = each.value.subnet_name
  resource_group_name  = data.azurerm_resource_group.exercise1.name
  virtual_network_name = azurerm_virtual_network.vnet[each.value.vnet_name].name
  address_prefixes     = [cidrsubnet(azurerm_virtual_network.vnet[each.value.vnet_name].address_space[0], each.value.newbits, each.value.netnum)]

  depends_on = [
    azurerm_virtual_network.vnet
  ]
}



variable "rules_file" {
  description = "The path to the CSV file containing the rules"
  type        = string
  default     = "rules.csv"
}

locals {
  rules_csv = csvdecode(file(var.rules_file))
  nsg_name = { for subnet in local.flat_subnets : "${subnet.vnet_name}-${subnet.subnet_name}" => {
    name = "${subnet.vnet_name}-${subnet.subnet_name}"
  } }
}

resource "azurerm_network_security_group" "this" {
  for_each = local.nsg_name

  name                = each.value.name
  location            = data.azurerm_resource_group.exercise1.location
  resource_group_name = data.azurerm_resource_group.exercise1.name

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

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = local.nsg_name

  subnet_id                 = azurerm_subnet.subnet[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id

  depends_on = [
    azurerm_subnet.subnet,
    azurerm_network_security_group.this
  ]
}