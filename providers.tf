terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    nullplatform = {
      source  = "nullplatform/nullplatform"
      version = "~> 0.0.63"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "nullplatform" {
  api_key = var.np_api_key
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null
}

provider "kubernetes" {
  host                   = module.eks.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.eks_cluster_ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = concat(
      var.aws_profile != "" ? ["--profile", var.aws_profile] : [],
      [
        "eks", "get-token",
        "--cluster-name", module.eks.eks_cluster_name
      ]
    )
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.eks_cluster_ca)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = concat(
        var.aws_profile != "" ? ["--profile", var.aws_profile] : [],
        [
          "eks", "get-token",
          "--cluster-name", module.eks.eks_cluster_name
        ]
      )
    }
  }
}