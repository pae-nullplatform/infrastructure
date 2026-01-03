# ============================================================================
# Account Configuration
# ============================================================================

variable "account" {
  description = "Account name"
  type        = string
}

variable "organization" {
  description = "Organization name"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "domain_name" {
  description = "Base domain name for DNS"
  type        = string
}

variable "nrn" {
  description = "Nullplatform NRN identifier"
  type        = string
}

variable "np_api_key" {
  description = "Nullplatform API key"
  type        = string
  sensitive   = true
}

variable "tags_selectors" {
  description = "Tags for resource selection"
  type        = map(string)
}

# ============================================================================
# AWS Configuration
# ============================================================================

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile name"
  type        = string
  default     = ""
}

# ============================================================================
# VPC Configuration
# ============================================================================

variable "vpc" {
  description = "VPC configuration including AZs, CIDR block, and subnets"
  type = object({
    azs             = list(string)
    cidr_block      = string
    public_subnets  = list(string)
    private_subnets = list(string)
  })
}

# ============================================================================
# GitHub Configuration
# ============================================================================

variable "github_installation_id" {
  description = "GitHub App installation ID"
  type        = string
}

variable "github_organization" {
  description = "GitHub organization name"
  type        = string
}

# ============================================================================
# Kubernetes Configuration
# ============================================================================

variable "namespace" {
  description = "Kubernetes namespace for nullplatform tools"
  type        = string
}

variable "k8s_provider" {
  description = "Kubernetes provider type"
  type        = string
}

# ============================================================================
# Agent Configuration
# ============================================================================

variable "image_tag" {
  description = "Agent image tag"
  type        = string
}

variable "cloud_provider" {
  description = "Cloud provider name"
  type        = string
}

variable "dns_type" {
  description = "DNS type configuration"
  type        = string
}

variable "use_account_slug" {
  description = "Whether to use account slug"
  type        = bool
}

variable "image_pull_secrets" {
  description = "Image pull secrets for Kubernetes"
  type        = string
  default     = ""
}

variable "service_template" {
  description = "Path to Istio service template"
  type        = string
}

variable "initial_ingress_path" {
  description = "Path to initial ingress template"
  type        = string
}

variable "blue_green_ingress_path" {
  description = "Path to blue-green ingress template"
  type        = string
}

# ============================================================================
# DNS Configuration
# ============================================================================

variable "dns_provider_name" {
  description = "DNS provider name"
  type        = string
}

variable "policy" {
  description = "External DNS policy"
  type        = string
}

variable "resources" {
  description = "External DNS resources to watch"
  type        = list(string)
}
