###############################################################################
# VPC Config
################################################################################
module "vpc" {
  source       = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/vpc?ref=v1.31.0"
  account      = var.account
  organization = var.organization
  vpc          = var.vpc
}

###############################################################################
# EKS Config
################################################################################
module "eks" {
  source                  = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/eks?ref=feat/eks-auto-mode-tags-support"
  aws_subnets_private_ids = ["subnet-0c86be1073ba8eb46", "subnet-0b8d233011c7e1071"]
  aws_vpc_vpc_id          = "vpc-0322282e89387d6ea"
  name                    = var.cluster_name
  use_auto_mode           = true
  endpoint_public_access = var.endpoint_public_access
  endpoint_private_access = var.endpoint_private_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  access_entries = {
    # Admin con política de cluster completo
    "admin" = {
      principal_arn = "arn:aws:iam::827992710245:role/aws-reserved/sso.amazonaws.com/sa-east-1/AWSReservedSSO_AWS_PAE_DEV-Developer-Standard_03ae3de6ca2dcc0a"
      type          = "STANDARD"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

###############################################################################
# EKS Auto Mode - Custom NodeClass & NodePool (for node tagging)
################################################################################
resource "kubernetes_manifest" "node_class" {
  manifest = {
    apiVersion = "eks.amazonaws.com/v1"
    kind       = "NodeClass"
    metadata = {
      name = "tagged-nodes"
    }
    spec = {
      tags = var.node_tags
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_manifest" "node_pool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "general-purpose-tagged"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "eks.amazonaws.com"
            kind  = "NodeClass"
            name  = "tagged-nodes"
          }
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            }
          ]
        }
      }
      limits = {
        cpu    = "100"
        memory = "400Gi"
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
      }
    }
  }

  depends_on = [module.eks, kubernetes_manifest.node_class]
}

###############################################################################
# DNS Config
################################################################################
module "dns" {
  source      = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/route53?ref=v1.31.0"
  domain_name = var.domain_name
  vpc_id      = module.vpc.vpc_id

  depends_on = [module.vpc]
}

###############################################################################
# ALB Controller Config
################################################################################
module "alb_controller" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/alb_controller?ref=v1.31.0"

  aws_iam_openid_connect_provider = module.eks.eks_oidc_provider_arn
  cluster_name                    = module.eks.eks_cluster_name
  vpc_id                          = module.vpc.vpc_id

  depends_on = [module.eks]
}

###############################################################################
# Code Repository
################################################################################
module "nullplatform_code_repository" {
  source                 = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/code_repository?ref=v1.31.0"
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
  source                 = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/cloud/aws/cloud?ref=v1.31.0"
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
  source       = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/asset/ecr?ref=v1.31.0"
  nrn          = var.nrn
  np_api_key   = var.np_api_key
  cluster_name = module.eks.eks_cluster_name
}

###############################################################################
# Dimensions
################################################################################
module "nullplatform_dimension" {
  source     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/dimensions?ref=v1.31.0"
  np_api_key = var.np_api_key
  nrn        = var.nrn
}

###############################################################################
# Nullplatform Base
################################################################################
module "nullplatform_base" {
  source                   = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/base?ref=v1.31.0"
  nrn                      = var.nrn
  k8s_provider             = var.k8s_provider
  np_api_key               = var.np_api_key
  gateway_internal_enabled = true
  gateway_private_aws_security_group_id = module.base_security.private_gateway_security_group_id
  gateway_public_aws_security_group_id = module.base_security.public_gateway_security_group_id
}


module "base_security" {
  source       = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/security?ref=v1.31.0"
  cluster_name = module.eks.eks_cluster_name
  gateway_internal_enabled = true
}


###############################################################################
# Prometheus Config
################################################################################
module "nullplatform_prometheus" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/prometheus?ref=v1.31.0"
}

module "agent" {
  source                  = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/agent?ref=v1.31.0"
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
  api_key = module.agent_api_key.api_key

  depends_on = [module.eks]
}

module "scope_definition" {
  source                   = "git::https://github.com/nullplatform/tofu-modules.git///nullplatform/scope_definition?ref=v1.31.0"
  nrn                      = var.nrn
  np_api_key               = var.np_api_key
  service_spec_name        = "AgentScope"
  service_spec_description = "Deployments using agent scopes"

}

module "scope_definition_agent_association" {
  source                     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition_agent_association?ref=v1.31.0"
  nrn                        = var.nrn
  tags_selectors             = var.tags_selectors
  api_key                    = module.scope_definition_agent_association_api_key.api_key
  scope_specification_id     = module.scope_definition.service_specification_id
  scope_specification_slug   = module.scope_definition.service_slug
}

module "scope_definition_agent_association_api_key" {
  source             = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/api_key?ref=v1.31.0"
  type               = "scope_notification"
  nrn                = var.nrn
  specification_slug = "k8s"
}
###############################################################################
# Agent IAM
################################################################################

module "agent_iam" {
  source                              = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/aws/iam/agent?ref=v1.31.0"
  aws_iam_openid_connect_provider_arn = module.eks.eks_oidc_provider_arn

  agent_namespace = var.namespace
  cluster_name    = var.cluster_name
}

module "agent_api_key" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/api_key?ref=v1.31.0"
  type   = "agent"
  nrn    = var.nrn
}

module "istio" {
  source = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/istio?ref=v1.31.0"

  depends_on = [module.eks, module.alb_controller]
}

module "external_dns_iam" {
  source                              = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/aws/iam/external_dns?ref=v1.31.0"
  aws_iam_openid_connect_provider_arn = module.eks.eks_oidc_provider_arn
  cluster_name                        = var.cluster_name
  hosted_zone_private_id              = module.dns.private_zone_id
  hosted_zone_public_id               = module.dns.public_zone_id
}

module "external_dns" {
  source            = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/external_dns?ref=v1.31.0"
  aws_region        = var.aws_region
  dns_provider_name = var.dns_provider_name
  domain_filters    = var.domain_name
  aws_iam_role_arn  = module.external_dns_iam.nullplatform_external_dns_role_arn
  zone_id_filter    = module.dns.public_zone_id
  zone_type         = "public"
  policy            = var.policy
  sources           = var.resources
  type              = "public"
  create_namespace = true


  depends_on = [module.alb_controller]
}

module "external_dns_private" {
  source            = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/external_dns?ref=v1.31.0"
  aws_region        = var.aws_region
  dns_provider_name = var.dns_provider_name
  domain_filters    = var.domain_name
  aws_iam_role_arn  = module.external_dns_iam.nullplatform_external_dns_role_arn
  zone_id_filter    = module.dns.private_zone_id
  zone_type         = "private"
  policy            = var.policy
  sources           = var.resources
  type              = "private"
  create_namespace = false

  depends_on = [module.alb_controller]
}

module "cert_manager_iam" {
  source                              = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/iam/cert_manager?ref=v1.31.0"
  cluster_name                        = var.cluster_name
  aws_iam_openid_connect_provider_arn = module.eks.eks_oidc_provider_arn
  hosted_zone_public_id               = module.dns.public_zone_id
  hosted_zone_private_id              = module.dns.private_zone_id
}

module "cert_manager" {
  source              = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/cert_manager?ref=v1.31.0"
  aws_region          = var.aws_region
  aws_sa_arn          = module.cert_manager_iam.nullplatform_cert_manager_role_arn
  cloud_provider      = "aws"
  private_domain_name = module.dns.private_zone_name
  account_slug        = var.account
  hosted_zone_name    = module.dns.public_zone_name

  depends_on = [module.alb_controller]
}



