###############################################################################
# VPC Config
################################################################################
module "foundations_vpc" {
  source       = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/vpc?ref=v1.0.0"
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
module "foundations_eks" {
  source                  = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/eks?ref=v1.11.0"
  aws_subnets_private_ids = module.foundations_vpc.private_subnets
  aws_vpc_vpc_id          = module.foundations_vpc.vpc_id
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
module "foundations_dns" {
  source      = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/route53?ref=v1.0.2"
  domain_name = var.domain_name
  vpc_id      = module.foundations_vpc.vpc_id
}

###############################################################################
# ALB Controller Config
################################################################################
module "foundations_alb_controller" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/alb_controller?ref=v1.0.0"

  aws_iam_openid_connect_provider = module.foundations_eks.eks_oidc_provider_arn
  cluster_name                    = module.foundations_eks.eks_cluster_name
  vpc_id                          = module.foundations_vpc.vpc_id

  depends_on = [module.foundations_eks]
}

###############################################################################
# Ingress Config
################################################################################
# module "foundations_networking" {
#   source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/ingress?ref=v1.0.0"
#
#   certificate_arn = module.foundations_dns.acm_certificate_arn
#
#   depends_on = [module.foundations_alb_controller]
# }

###############################################################################
# Code Repository
################################################################################
module "nullplatform_code_repository" {
  source           = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/code_repository?ref=v1.0.2"
  np_api_key       = var.np_api_key
  nrn              = var.nrn
  git_provider           = "github"
  organization_installation_id = var.github_installation_id
  organization = var.github_organization

  # group_path       = var.group_path
  # access_token     = var.access_token
  # installation_url = var.installation_url
  # collaborators_config = var.collaborators_config
  # gitlab_repository_prefix = var.gitlab_repository_prefix
  # gitlab_slug = var.gitlab_slug
}

###############################################################################
# Cloud Providers Config
################################################################################
module "nullplatform_cloud_provider" {
  source                 = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/cloud/aws/cloud?ref=v1.0.0"
  domain_name            = var.domain_name
  hosted_private_zone_id = module.foundations_dns.private_zone_id
  hosted_public_zone_id  = module.foundations_dns.public_zone_id
  np_api_key             = var.np_api_key
  nrn                    = var.nrn
}

###############################################################################
# Asset Repository
################################################################################
module "nullplatform_asset_respository" {
  source     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/asset/ecr?ref=v1.0.0"
  nrn        = var.nrn
  np_api_key = var.np_api_key
}

###############################################################################
# Dimensions
################################################################################
module "nullplatform_dimension" {
  source     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/dimensions?ref=v1.0.0"
  np_api_key = var.np_api_key
  nrn        = var.nrn
}

###############################################################################
# Nullplatform Base
################################################################################
module "nullplatform_base" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/cloud/aws/base?ref=v1.0.0"
  nrn    = var.nrn
  depends_on = [module.foundations_eks]
}


###############################################################################
# Prometheus Config
################################################################################
module "nullplatform_prometheus" {
  source     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/prometheus?ref=v1.0.0"
  np_api_key = var.np_api_key
  nrn        = var.nrn

}

module "nullplatform_scope_agent" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/agent?ref=v1.12.4"

  cluster_name                        = module.foundations_eks.eks_cluster_name
  nrn                                 = var.nrn
  tags_selectors                      = var.tags_selectors
  cloud_provider                      = var.cluster_provider
  image_tag                           = var.image_tag
  aws_iam_role_arn = module.agent_iam.nullplatform_agent_role_arn
  extra_config     = var.extra_config
}

module "scope_definition" {
  source     = "git::https://github.com/nullplatform/tofu-modules.git///nullplatform/scope_definition?ref=v1.12.3"
  nrn        = var.nrn
  np_api_key = var.np_api_key
  service_spec_name                   = "AgentScope"
  service_spec_description            = "Deployments using agent scopes"

}

module "scope_definition_agent_association" {
  source                     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition_agent_association?ref=v1.12.3"
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
  source                              = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/aws/iam?ref=v1.12.4"
  aws_iam_openid_connect_provider_arn = module.foundations_eks.eks_oidc_provider_arn

  agent_namespace = var.namespace
  cluster_name    = var.cluster_name
}

module "istio" {
  source = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/istio?ref=v1.12.3"
}

resource "kubernetes_namespace_v1" "nullplatform" {
  metadata {
    name = "nullplatform"
  }
}

resource "kubernetes_namespace_v1" "gateway" {
  metadata {
    name = "gateway"
  }
}

resource "kubernetes_manifest" "gateway-public" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"

    metadata = {
      name      = "gateway-public"
      namespace = "gateway"

      labels = {
        "app" = "gateway-public"
      }

      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-name"                 = "k8s-nullplatform-internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-type"                 = "nlb"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"               = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"      = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"             = module.foundations_dns.acm_certificate_arn
        "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"            = "443"
        "service.beta.kubernetes.io/aws-load-balancer-backend-protocol"     = "tcp"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port"     = "15021"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol" = "http"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path"     = "/healthz/ready"
      }
    }

    spec = {
      gatewayClassName = "istio"

      listeners = [
        {
          name     = "https"
          hostname = "*.${var.domain_name}"
          port     = 443
          protocol = "HTTP"

          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        {
          name     = "http"
          hostname = "*.${var.domain_name}"
          port     = 80
          protocol = "HTTP"

          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        }
      ]
    }
  }
  depends_on = [module.foundations_eks, module.foundations_alb_controller]
}

resource "kubernetes_manifest" "ext_authz_smoke" {
  manifest = {
    apiVersion = "security.istio.io/v1"
    kind       = "AuthorizationPolicy"

    metadata = {
      name      = "ext-authz-smoke"
      namespace = "gateway"
    }

    spec = {
      selector = {
        matchLabels = {
          app = "gateway-public"
        }
      }

      action = "CUSTOM"

      provider = {
        name = "opa-ext-authz"
      }

      rules = [
        {
          to = [
            {
              operation = {
                paths = [
                  "/smoke",
                  "/smoke/*"
                ]
              }
            }
          ]
        }
      ]
    }
  }
  depends_on = [module.istio]
}