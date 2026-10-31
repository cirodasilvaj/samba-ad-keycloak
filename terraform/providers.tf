terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }

  # Bucket, key, region and use_lockfile are injected at `terraform init` time
  # via -backend-config flags in .github/workflows/deploy.yml.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "samba-ad-keycloak"
      ManagedBy = "terraform"
      Cluster   = var.eks_cluster_name
    }
  }
}

# Look up the existing EKS cluster to automatically join its VPC and subnets
data "aws_eks_cluster" "target" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "target" {
  name = var.eks_cluster_name
}

data "aws_vpc" "target" {
  id = data.aws_eks_cluster.target.vpc_config[0].vpc_id
}

# Discover private subnets inside the EKS VPC (fallback to all cluster subnets)
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.target.id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

# Latest Ubuntu 24.04 LTS (Noble) AMD64 AMI in the target region
data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.target.token
}

locals {
  cluster_subnet_ids = tolist(data.aws_eks_cluster.target.vpc_config[0].subnet_ids)
  private_subnet_ids = length(data.aws_subnets.private.ids) >= 2 ? data.aws_subnets.private.ids : local.cluster_subnet_ids
  subnet_az1_id      = local.private_subnet_ids[0]
  subnet_az2_id      = local.private_subnet_ids[1 % length(local.private_subnet_ids)]
}
