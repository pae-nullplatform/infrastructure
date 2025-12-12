###############################################################################
# VPC Config
################################################################################
module "foundations_vpc" {
  source       = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/vpc?ref=v1.12.3"
  account      = var.account
  organization = var.organization
  vpc          = var.vpc
}

###############################################################################
# EKS Config
################################################################################
module "foundations_eks" {
  source                  = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/eks?ref=v1.12.3"
  aws_subnets_private_ids = module.foundations_vpc.private_subnets
  aws_vpc_vpc_id          = module.foundations_vpc.vpc_id
  name                    = var.cluster_name
  use_auto_mode           = true
}

###############################################################################
# DNS Config
################################################################################
module "foundations_dns" {
  source      = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/route53?ref=v1.12.3"
  domain_name = var.domain_name
  vpc_id      = module.foundations_vpc.vpc_id
}

##############################################################################
#ALB Controller Config
###############################################################################
module "foundations_alb_controller" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/alb_controller?ref=feature/add-output-auth"

  aws_iam_openid_connect_provider = module.foundations_eks.eks_oidc_provider_arn
  cluster_name                    = module.foundations_eks.eks_cluster_name
  vpc_id                          = module.foundations_vpc.vpc_id

  depends_on = [module.foundations_eks]
}

##############################################################################
#Ingress Config
###############################################################################
# module "foundations_networking" {
#   source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/ingress?ref=v1.12.3"
#
#   certificate_arn = module.foundations_dns.acm_certificate_arn
#
#   depends_on = [module.foundations_alb_controller]
# }

###############################################################################
# Code Repository
################################################################################
module "nullplatform_code_repository" {
  source                   = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/code_repository?ref=v1.12.3"
  np_api_key               = var.np_api_key
  nrn                      = var.nrn
  git_provider             = "github"
  github_installation_id = var.github_installation_id
  github_organization = var.github_organization

}

###############################################################################
# Cloud Providers Config
################################################################################
module "nullplatform_cloud_provider" {
  source                 = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/cloud/aws/cloud?ref=v1.12.3"
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
  source     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/asset/ecr?ref=feature/add-output-auth"
  nrn        = var.nrn
  np_api_key = var.np_api_key
  cluster_name = var.cluster_name
}

###############################################################################
# Dimensions
################################################################################
module "nullplatform_dimension" {
  source     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/dimensions?ref=v1.12.3"
  np_api_key = var.np_api_key
  nrn        = var.nrn
}

###############################################################################
# Nullplatform API KEY
################################################################################
module "authorization" {
  source       = "git::https://github.com/nullplatform/tofu-modules.git///nullplatform/authorization?ref=feature/add-output-auth"
  nrn          = var.nrn
  destination  = "nullplatform-base"
  np_api_key   = var.np_api_key
}
###############################################################################
# Nullplatform Base
################################################################################
module "nullplatform_base" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/base?ref=feature/add-output-auth"
  nrn    = var.nrn
  np_api_key     = module.authorization.authorization_api_key
  k8s_provider   = "eks"
  depends_on = [module.foundations_eks]

}


###############################################################################
# Prometheus Config
################################################################################
module "nullplatform_prometheus" {
  source     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/prometheus?ref=v1.12.3"
  np_api_key = var.np_api_key
  nrn        = var.nrn

}

module "scope_definition" {
  source     = "git::https://github.com/nullplatform/tofu-modules.git///nullplatform/scope_definition?ref=v1.12.3"
  nrn        = var.nrn
  np_api_key = var.np_api_key

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
  source          = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/aws/iam?ref=feature/add-output-auth"
  aws_iam_openid_connect_provider_arn = module.foundations_eks.eks_oidc_provider_arn

  agent_namespace = var.namespace
  cluster_name    = var.cluster_name
}

###############################################################################
# Nullplatform Scope
################################################################################
module "cloud_aws_agent" {
  source                              = "git::https://github.com/nullplatform/tofu-modules.git///nullplatform/agent?ref=feature/add-output-auth"
  cloud_provider                      = var.cluster_provider
  cluster_name                        = var.cluster_name
  image_tag                           = var.image_tag
  nrn                                 = var.nrn
  aws_iam_role_arn = module.agent_iam.nullplatform_agent_role_arn
  extra_config = var.extra_config
  tags_selectors = var.tags_selectors
}

module "istio" {
  source                       = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/istio?ref=v1.12.3"
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
        "service.beta.kubernetes.io/aws-load-balancer-type"            = "nlb"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"        = module.foundations_dns.acm_certificate_arn
        "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"       = "443"
        "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "tcp"

        # Health check configurado para usar el puerto 15021 de Istio
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
  depends_on = [module.foundations_eks]
}

# resource "kubernetes_manifest" "smoke_request_authn" {
#   manifest = {
#     apiVersion = "security.istio.io/v1"
#     kind       = "RequestAuthentication"
#     metadata = {
#       name      = "smoke-jwt"
#       namespace = "istio-system"
#     }
#     spec = {
#       selector = {
#         matchLabels = {
#           "app" = "gateway-public"
#         }
#       }
#       jwtRules = [
#         {
#           issuer = "testing@secure.istio.io"
#           jwksUri =  "https://raw.githubusercontent.com/istio/istio/release-1.28/security/tools/jwt/samples/jwks.json"
#           forwardOriginalToken = true
#         }
#       ]
#     }
#   }
#   depends_on = [module.foundations_eks]
# }
#
# resource "kubernetes_manifest" "smoke_allow_policy" {
#   manifest = {
#     apiVersion = "security.istio.io/v1"
#     kind       = "AuthorizationPolicy"
#     metadata = {
#       name      = "allow-smoke-with-jwt"
#       namespace = "istio-system"
#     }
#     spec = {
#       selector = {
#         matchLabels = {
#           "app" = "gateway-public"
#         }
#       }
#       action = "ALLOW"
#       rules = [
#         {
#           to = [
#             {
#               operation = {
#                 paths   = ["/smoke", "/smoke/*"]
#                 methods = ["GET", "POST"]
#               }
#             }
#           ]
#           when = [
#             {
#               key    = "request.auth.claims[foo]"
#               values = ["bar"]
#             }
#           ]
#         }
#       ]
#     }
#   }
#   depends_on = [module.foundations_eks]
# }
#
# resource "kubernetes_manifest" "public_allow_policy" {
#   manifest = {
#     apiVersion = "security.istio.io/v1"
#     kind       = "AuthorizationPolicy"
#     metadata = {
#       name      = "allow-non-smoke-public"
#       namespace = "istio-system"
#     }
#     spec = {
#       selector = {
#         matchLabels = {
#           "app" = "gateway-public"
#         }
#       }
#       action = "ALLOW"
#       rules = [
#         {
#           to = [
#             {
#               operation = {
#                 notPaths = ["/smoke", "/smoke/*"]
#               }
#             }
#           ]
#         }
#       ]
#     }
#   }
#   depends_on = [module.foundations_eks]
# }



