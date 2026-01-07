###############################################################################
# VPC Config
################################################################################
module "vpc" {
  source       = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/vpc?ref=v1.15.1"
  account      = var.account
  organization = var.organization
  vpc          = var.vpc
}

# ########################################################
# # IAM Rol para ver cluster
# ########################################################
# resource "aws_iam_role" "eks_admin" {
#   name = "${var.cluster_name}-admin-role"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           AWS = "arn:aws:iam::843443650160:role/aws-reserved/sso.amazonaws.com/sa-east-1/AWSReservedSSO_AWSAdministratorAccess_cf36aa73feaf2f63"
#         }
#       }
#     ]
#   })
# }

###############################################################################
# EKS Config
################################################################################
module "eks" {
  source                  = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/eks?ref=v1.15.1"
  aws_subnets_private_ids = module.vpc.private_subnets
  aws_vpc_vpc_id          = module.vpc.vpc_id
  name                    = var.cluster_name
  use_auto_mode           = true
  access_entries = {
    # # Admin con política de cluster completo
    # "admin" = {
    #   principal_arn = aws_iam_role.eks_admin.arn
    #   type          = "STANDARD"
    #   policy_associations = {
    #     admin = {
    #       policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
    #       access_scope = {
    #         type = "cluster"
    #       }
    #     }
    #   }
    # }
  }
}

###############################################################################
# DNS Config
################################################################################
module "dns" {
  source      = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/route53?ref=v1.15.1"
  domain_name = var.domain_name
  vpc_id      = module.vpc.vpc_id

  depends_on = [module.vpc]
}

###############################################################################
# ALB Controller Config
################################################################################
module "alb_controller" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/alb_controller?ref=v1.15.1"

  aws_iam_openid_connect_provider = module.eks.eks_oidc_provider_arn
  cluster_name                    = module.eks.eks_cluster_name
  vpc_id                          = module.vpc.vpc_id

  depends_on = [module.eks]
}

###############################################################################
# Code Repository
################################################################################
module "nullplatform_code_repository" {
  source                 = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/code_repository?ref=v1.15.1"
  np_api_key             = var.np_api_key
  nrn                    = var.nrn
  git_provider           = "github"
  github_installation_id = var.github_installation_id
  github_organization    = var.github_organization
}

###############################################################################
# Cloud Providers Config
################################################################################
module "nullplatform_cloud_provider" {
  source                 = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/cloud/aws/cloud?ref=v1.15.1"
  domain_name            = var.domain_name
  hosted_private_zone_id = module.dns.private_zone_id
  hosted_public_zone_id  = module.dns.public_zone_id
  np_api_key             = var.np_api_key
  nrn                    = var.nrn
}

###############################################################################
# Asset Repository
################################################################################
module "nullplatform_asset_repository" {
  source       = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/asset/ecr?ref=v1.15.1"
  nrn          = var.nrn
  np_api_key   = var.np_api_key
  cluster_name = module.eks.eks_cluster_name
}

###############################################################################
# Dimensions
################################################################################
module "nullplatform_dimension" {
  source     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/dimensions?ref=v1.15.1"
  np_api_key = var.np_api_key
  nrn        = var.nrn
}

###############################################################################
# Nullplatform Base
################################################################################
module "nullplatform_base" {
  source       = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/base?ref=v1.15.1"
  nrn          = var.nrn
  k8s_provider = var.k8s_provider
  np_api_key   = var.np_api_key
}


###############################################################################
# Prometheus Config
################################################################################
module "nullplatform_prometheus" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/prometheus?ref=v1.15.1"
}

module "agent" {
  source                  = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/agent?ref=v1.16.0"
  cluster_name            = var.cluster_name
  nrn                     = var.nrn
  tags_selectors          = var.tags_selectors
  image_tag               = var.image_tag
  aws_iam_role_arn        = module.agent_iam.nullplatform_agent_role_arn
  cloud_provider          = var.cloud_provider
  domain                  = var.domain_name
  dns_type                = var.dns_type
  use_account_slug        = var.use_account_slug
  image_pull_secrets      = var.image_pull_secrets
  service_template        = var.service_template
  initial_ingress_path    = var.initial_ingress_path
  blue_green_ingress_path = var.blue_green_ingress_path

  depends_on = [module.eks]
}

module "scope_definition" {
  source                   = "git::https://github.com/nullplatform/tofu-modules.git///nullplatform/scope_definition?ref=v1.15.1"
  nrn                      = var.nrn
  np_api_key               = var.np_api_key
  service_spec_name        = "AgentScope"
  service_spec_description = "Deployments using agent scopes"

}

module "scope_definition_agent_association" {
  source                     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition_agent_association?ref=v1.15.1"
  nrn                        = var.nrn
  np_api_key                 = var.np_api_key
  service_specification_id   = module.scope_definition.service_specification_id
  service_specification_slug = module.scope_definition.service_slug
  tags_selectors             = var.tags_selectors
}
###############################################################################
# Agent IAM
################################################################################

module "agent_iam" {
  source                              = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/aws/iam/agent?ref=v1.15.1"
  aws_iam_openid_connect_provider_arn = module.eks.eks_oidc_provider_arn

  agent_namespace = var.namespace
  cluster_name    = var.cluster_name
}

module "istio" {
  source = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/istio?ref=v1.15.1"

  depends_on = [module.eks, module.alb_controller]
}

module "external_dns_iam" {
  source                              = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/aws/iam/external_dns?ref=v1.15.1"
  aws_iam_openid_connect_provider_arn = module.eks.eks_oidc_provider_arn
  cluster_name                        = var.cluster_name
  hosted_zone_private_id              = module.dns.private_zone_id
  hosted_zone_public_id               = module.dns.public_zone_id
}

module "external_dns" {
  source                 = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/external_dns?ref=v1.15.1"
  aws_region             = var.aws_region
  dns_provider_name      = var.dns_provider_name
  domain_filters         = var.domain_name
  aws_iam_role_arn       = module.external_dns_iam.nullplatform_external_dns_role_arn
  private_hosted_zone_id = module.dns.private_zone_id
  public_hosted_zone_id  = module.dns.public_zone_id
  policy                 = var.policy
  sources                = var.resources

  depends_on = [module.alb_controller]
}

module "cert_manager_iam" {
  source                              = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/iam/cert_manager?ref=v1.15.1"
  cluster_name                        = var.cluster_name
  aws_iam_openid_connect_provider_arn = module.eks.eks_oidc_provider_arn
  hosted_zone_public_id               = module.dns.public_zone_id
  hosted_zone_private_id              = module.dns.private_zone_id
}

module "cert_manager" {
  source              = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/cert_manager?ref=v1.15.1"
  aws_region          = var.aws_region
  aws_sa_arn          = module.cert_manager_iam.nullplatform_cert_manager_role_arn
  cloud_provider      = "aws"
  private_domain_name = module.dns.private_zone_name
  account_slug        = var.account
  hosted_zone_name    = module.dns.public_zone_name

  depends_on = [module.alb_controller]
}



