###############################################################################
# Azure VNet Module
# Creates virtual network and subnets for AKS
###############################################################################

variable "create" {
  description = "Whether to create the VNet"
  type        = bool
}

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "address_space" {
  description = "Address space for the VNet"
  type        = list(string)
}

variable "subnet_prefixes" {
  description = "Address prefixes for subnets"
  type        = list(string)
}

variable "subnet_names" {
  description = "Names for subnets"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
}
