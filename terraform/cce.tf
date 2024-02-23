variable "access_key" {
  description = "access_key"
  sensitive = true
}

variable "secret_key" {
  description = "secret_key"
  sensitive = true
}

variable "password" {
  description = "password"
  sensitive = true
}

variable "my_key" {
  description = "my_key"
  sensitive = true
}

terraform {
  required_providers {
    sbercloud = {
      source  = "tf.repo.sbc.space/sbercloud-terraform/sbercloud" # Initialize Advanced provider
    }
    # kubernetes = {
    #   source = "hashicorp/kubernetes"
    # }
  }
}

# Configure Advanced provider
provider "sbercloud" {
  auth_url = "https://iam.ru-moscow-1.hc.sbercloud.ru/v3" # Authorization address
  region   = "ru-moscow-1" # The region where the cloud infrastructure will be deployed

  # Authorization keys
  access_key = var.access_key
  secret_key = var.secret_key

}

data "sbercloud_images_image" "centos_image" {
  name = "CentOS 7.6 64bit"
  most_recent = true
}

# Get list of AZ
data "sbercloud_availability_zones" "list_of_az" {}

# output "list_of_az" {
#   value = data.sbercloud_availability_zones.list_of_az.names
# }

# Get suitable flavors
data "sbercloud_compute_flavors" "flavors" {
  availability_zone = data.sbercloud_availability_zones.list_of_az.names[0]
  performance_type  = "normal"
  cpu_core_count    = 2
  memory_size       = 4
}

# output "suitable_flavors" {
#   value = data.sbercloud_compute_flavors.flavors.ids
# }

## Get all compute flavors
# data "sbercloud_compute_flavors" "all_flavors" {}

# output "all_sbercloud_compute_flavors" {
#   value = data.sbercloud_compute_flavors.all_flavors.ids
# }

# Define local variables
locals {
  number_of_az  = length(data.sbercloud_availability_zones.list_of_az.names)
  
  rules = {
    http-rule = {
      description = "Allow HTTP from anywhere",
      protocol = "tcp",
      port = 80,
      source = "0.0.0.0/0"
    },
    ssh-rule = {
      description = "Allow SSH from anywhere",
      protocol = "tcp",
      port = 22,
      source = "0.0.0.0/0"
    }
  }
}

#Create key pair
resource "sbercloud_compute_keypair" "my_keypair" {
  name       = "my_keypair"
  public_key = var.my_key
}

# Create VPC
resource "sbercloud_vpc" "vpc_01" {
  name = "vpc-main"
  cidr = "10.33.0.0/16"
}

# Create subnets
resource "sbercloud_vpc_subnet" "subnet_01" {
  name       = "subnet-one"
  cidr       = "10.33.10.0/24"
  gateway_ip = "10.33.10.1"

  primary_dns   = "100.125.13.59"
  secondary_dns = "8.8.8.8"

  vpc_id = sbercloud_vpc.vpc_01.id
}

resource "sbercloud_vpc_subnet" "subnet_02" {
  name       = "subnet-two"
  cidr       = "10.33.20.0/24"
  gateway_ip = "10.33.20.1"

  primary_dns   = "100.125.13.59"
  secondary_dns = "8.8.8.8"

  vpc_id = sbercloud_vpc.vpc_01.id
}

# Create security group
resource "sbercloud_networking_secgroup" "sg_01" {
  name        = "sg-main"
  description = "Security group for HTTP + SSH"
}

# Create all security group rules
resource "sbercloud_networking_secgroup_rule" "sg_rule_01" {
  for_each = local.rules

  direction         = "ingress"
  ethertype         = "IPv4"
  description       = each.value.description
  protocol          = each.value.protocol
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = each.value.source

  security_group_id = sbercloud_networking_secgroup.sg_01.id
}

# Create EIPs
resource "sbercloud_vpc_eip" "nat_eip" {
  publicip {
    type = "5_bgp"
  }

  bandwidth {
    name        = "nat-bandwidth"
    size        = 4
    share_type  = "PER"
    charge_mode = "bandwidth"
  }
}

resource "sbercloud_vpc_eip" "ecs_eip" {
  publicip {
    type = "5_bgp"
  }

  bandwidth {
    name        = "cce-bandwidth"
    size        = 4
    share_type  = "PER"
    charge_mode = "bandwidth"
  }
}

resource "sbercloud_vpc_eip" "elb_eip" {
  publicip {
    type = "5_bgp"
  }

  bandwidth {
    name        = "cce-bandwidth"
    size        = 4
    share_type  = "PER"
    charge_mode = "bandwidth"
  }
}

# Create NAT Gateway
resource "sbercloud_nat_gateway" "nat_gw" {
  name        = "nat-main"
  description = "NAT Gateway"
  spec        = "1"
  vpc_id      = sbercloud_vpc.vpc_01.id
  subnet_id   = sbercloud_vpc_subnet.subnet_01.id
}

# Create SNAT rules
resource "sbercloud_nat_snat_rule" "snat_subnet_01" {
  nat_gateway_id = sbercloud_nat_gateway.nat_gw.id
  subnet_id      = sbercloud_vpc_subnet.subnet_01.id
  floating_ip_id = sbercloud_vpc_eip.nat_eip.id
}

resource "sbercloud_nat_snat_rule" "snat_subnet_02" {
  nat_gateway_id = sbercloud_nat_gateway.nat_gw.id
  subnet_id      = sbercloud_vpc_subnet.subnet_02.id
  floating_ip_id = sbercloud_vpc_eip.nat_eip.id
}

resource "sbercloud_lb_loadbalancer" "elb_01" {
  name          = "elb"
  vip_subnet_id = sbercloud_vpc_subnet.subnet_02.subnet_id
}

# Attach EIP to ELB
resource "sbercloud_networking_eip_associate" "elb_eip_associate" {
  public_ip = sbercloud_vpc_eip.elb_eip.address
  port_id   = sbercloud_lb_loadbalancer.elb_01.vip_port_id
}

# Create CCE cluster
resource "sbercloud_cce_cluster" "cce_01" {
  name                   = "cce-cluster"
  flavor_id              = "cce.s2.small"
  container_network_type = "overlay_l2"
  multi_az               = true
  vpc_id                 = sbercloud_vpc.vpc_01.id
  subnet_id              = sbercloud_vpc_subnet.subnet_02.id
}

# Create CCE worker node(s)
resource "sbercloud_cce_node" "cce_01_node" {
  count             = 3
  cluster_id        = sbercloud_cce_cluster.cce_01.id
  name              = "cce-worker-${count.index}"
  flavor_id         = data.sbercloud_compute_flavors.flavors.ids[0]
  availability_zone = data.sbercloud_availability_zones.list_of_az.names[count.index % local.number_of_az]
  os                = "CentOS 7.6"
  password          = var.password

  root_volume {
    size       = 40
    volumetype = "SAS"
  }

  data_volumes {
    size       = 100
    volumetype = "SAS"
  }
}

#Cloud-init file for ECS with Ansible
data "template_file" "user_data" {
  template = file("./ansible-ecs-init.yaml")
}

# Create ECS for Ansible
resource "sbercloud_compute_instance" "ecs_01" {
  name              = "terraform-ecs"
  image_id          = data.sbercloud_images_image.centos_image.id
  flavor_id         = data.sbercloud_compute_flavors.flavors.ids[0]
  security_groups   = [sbercloud_networking_secgroup.sg_01.name]
  availability_zone = data.sbercloud_availability_zones.list_of_az.names[0]
  admin_pass        = var.password
  key_pair          = sbercloud_compute_keypair.my_keypair.name
  user_data         = data.template_file.user_data.rendered

  system_disk_type = "SAS"
  system_disk_size = 16

  network {
    uuid = sbercloud_vpc_subnet.subnet_02.id
  }
}

# Attach the EIP to the ECS
resource "sbercloud_compute_eip_associate" "associated_01" {
  public_ip   = sbercloud_vpc_eip.ecs_eip.address
  instance_id = sbercloud_compute_instance.ecs_01.id
}