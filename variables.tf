variable "instance_count" {
  default = 2
}

variable "subnet_cidr" {
  default = "10.0.1.0/24"
}

variable "address_space" {
  default = "10.0.0.0/16"
}

variable "subnet_name" {
  default = "SubnetA"
}

variable "network_name" {
  default = "test-network"
}

variable "resource_group_name" {
  default = "test-rg"
}

variable "location" {
  default = "westus3"
}

variable "size" {
  default = "Standard_B1ls"
}

variable "adminuser" {
  default = "adminuser"
}

variable "computer_host_name" {
  default = "hostname"
}

variable "port" {
  default = "22"
}