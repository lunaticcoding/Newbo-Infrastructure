terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.52.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
  }
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "random_password" "k3s_token" {
  length  = 64
  special = false
  upper   = true
  lower   = true
  numeric = true
}

variable "inter_node_private_key_path" {
  type        = string
  description = "Path to private SSH key file for inter-node communication"
}

variable "admin_cidrs" {
  type    = list(string)
}

locals {
  inter_node_private_key = file(pathexpand(var.inter_node_private_key_path))
}

resource "hcloud_network" "private_network" {
  name     = "kubernetes-cluster"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "private_network_subnet" {
  type         = "cloud"
  network_id   = hcloud_network.private_network.id
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

############################################
# Firewalls (absolute minimum)
############################################

# Master / server firewall
resource "hcloud_firewall" "k3s_master" {
  name = "k3s-master"

  # k3s API server for agents (and optionally for admin clients)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = concat([hcloud_network.private_network.ip_range], var.admin_cidrs)
  }

  # kubelet on the master node (server runs an agent too)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = [hcloud_network.private_network.ip_range]
  }

  # Flannel VXLAN (default k3s CNI) — node-to-node overlay
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8472"
    source_ips = [hcloud_network.private_network.ip_range]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.admin_cidrs
  }
}

# Worker firewall
resource "hcloud_firewall" "k3s_worker" {
  name = "k3s-worker"

  # kubelet on workers (control plane scrapes / execs via API)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "10250"
    source_ips = [hcloud_network.private_network.ip_range]
  }

  # Flannel VXLAN overlay traffic
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "8472"
    source_ips = [hcloud_network.private_network.ip_range]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.admin_cidrs
  }
}

##############################################

resource "hcloud_server" "master-node" {
  name        = "master-node"
  image       = "ubuntu-24.04"
  server_type = "cpx11"
  location    = "fsn1"

  ssh_keys = ["Newbo Terraform Key | Marco Papula"]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  firewall_ids = [hcloud_firewall.k3s_master.id]

  network {
    network_id = hcloud_network.private_network.id
    # IP Used by the master node, needs to be static
    # Here the worker nodes will use 10.0.1.1 to communicate with the master node
    ip         = "10.0.1.1"
  }

  user_data = templatefile("${path.module}/cloud-init-master.yaml", {
    inter_node_private_key = local.inter_node_private_key,
    k3s_token            = random_password.k3s_token.result
  })

  depends_on = [hcloud_network_subnet.private_network_subnet, local.inter_node_private_key]
}

resource "hcloud_server" "worker-nodes" {
  count = 3

  name        = "worker-node-${count.index}"
  image       = "ubuntu-24.04"
  server_type = "cpx11"
  location    = "fsn1"
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  ssh_keys = ["Newbo Terraform Key | Marco Papula"]

  firewall_ids = [hcloud_firewall.k3s_worker.id]

  network {
    network_id = hcloud_network.private_network.id
  }
  user_data = templatefile("${path.module}/cloud-init-worker.yaml", {
    inter_node_private_key = local.inter_node_private_key,
    k3s_token            = random_password.k3s_token.result
  })

  depends_on = [hcloud_network_subnet.private_network_subnet, hcloud_server.master-node, local.inter_node_private_key]
}

