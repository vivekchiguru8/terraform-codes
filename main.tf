terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = "project-8f3b3c8e-4647-4878-8b5"
  region  = "us-central1"
  zone    = "us-central1-a"
}

# 1. VPC with no auto subnets
resource "google_compute_network" "vpc_network" {
  name                    = "custom-vpc"
  auto_create_subnetworks = false
  mtu                     = 1460
}

# 2. Custom subnet
resource "google_compute_subnetwork" "custom_subnet" {
  name          = "custom-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc_network.id
} # <-- THIS BRACE WAS MISSING

# 3. Firewall for SSH + HTTP
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.name # <-- FIXED: was .vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh-enabled"]
}

resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = google_compute_network.vpc_network.name # <-- FIXED: was .vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

# 4. VM Instance
resource "google_compute_instance" "vm_instance" {
  name         = "my-vm"
  machine_type = "e2-medium"
  zone         = "us-central1-a"                # <-- FIXED: was us-central1
  tags         = ["ssh-enabled", "http-server"] # <-- ADDED: to match firewall rules

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.custom_subnet.id
    access_config {}
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_pub_key_path)}"
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    systemctl start nginx
    echo "Hello from Terraform" > /var/www/html/index.html
  EOF
}

# 5. Variables - YOU NEED THIS BLOCK
variable "ssh_user" {
  description = "SSH username"
  type        = string
  default     = "ubuntu"
}

variable "ssh_pub_key_path" {
  description = "Path to SSH public key"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}