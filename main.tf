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

# VPC network for the cluster
resource "google_compute_network" "vpc" {
  name                    = "gke-network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "gke-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "pod-range"
    ip_cidr_range = "10.20.0.0/16"
  }
  secondary_ip_range {
    range_name    = "svc-range"
    ip_cidr_range = "10.30.0.0/16"
  }
}

resource "google_container_cluster" "primary" {
  name     = "gke-standard-cluster"
  location = "us-central1"
  
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pod-range"
    services_secondary_range_name = "svc-range"
  }

  workload_identity_config {
    workload_pool = "project-8f3b3c8e-4647-4878-8b5.svc.id.goog"  # Fixed: use real project ID
  }

  private_cluster_config {
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }
} # <-- THIS BRACE WAS MISSING. Closes the cluster resource.

# Separate node pool - this is where your pods actually run
resource "google_container_node_pool" "primary_nodes" {
  name       = "primary-node-pool"
  location   = "us-central1"
  cluster    = google_container_cluster.primary.name
  node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 50
    disk_type    = "pd-standard"  # <-- REMOVED the extra } that was here
    
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      env = "dev"
    }
  } # <-- This closes node_config

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

output "kubeconfig_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${google_container_cluster.primary.location}"
}