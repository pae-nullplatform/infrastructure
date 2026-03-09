###############################################################################
# EKS Config
################################################################################
module "eks" {
  source                  = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/eks?ref=v1.42.0"
  aws_subnets_private_ids = ["subnet-05070032ec080012a", "subnet-00c0bdda437e22490"]
  aws_vpc_vpc_id          = "vpc-0a5dfe8e463dee15d"
  name                    = var.cluster_name
  use_auto_mode           = true
  auto_mode_node_pools    = ["general-purpose", "system"]
  endpoint_public_access       = var.endpoint_public_access
  endpoint_private_access      = var.endpoint_private_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  additional_network_cidrs     = ["100.17.0.0/16"]
  enabled_log_types            = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  access_entries = {
    admin_sso = {
      principal_arn = "arn:aws:iam::235494813897:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Administrator_cf6f7c1e79f4c2d3"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

###############################################################################
# DNS Config
################################################################################
module "dns" {
  source      = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/dns?ref=v1.42.0"
  domain_name = var.domain_name
  vpc_id      = "vpc-0a5dfe8e463dee15d"
}

###############################################################################
# ACM Config
################################################################################
module "acm" {
  source      = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/acm?ref=v1.42.0"
  domain_name = var.domain_name
  zone_id     = module.dns.public_zone_id
}

###############################################################################
# WAF Config
################################################################################
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.cluster_name}-waf"
  description = "WAF for public ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputsMetric"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IpReputationMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.cluster_name}-waf"
    sampled_requests_enabled   = true
  }
}


###############################################################################
# Code Repository
################################################################################
module "nullplatform_code_repository" {
  source                 = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/code_repository?ref=v1.42.0"
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
  source                 = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/cloud/aws/cloud?ref=v1.42.0"
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
  source       = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/asset/ecr?ref=v1.42.0"
  nrn          = var.nrn
  np_api_key   = var.np_api_key
  cluster_name = module.eks.eks_cluster_name
}

###############################################################################
# Dimensions
################################################################################
module "nullplatform_dimension" {
  source     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/dimensions?ref=v1.42.0"
  np_api_key = var.np_api_key
  nrn        = var.nrn
}

##############################################################################
#Nullplatform Base
###############################################################################
module "nullplatform_base" {
  source                                = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/base?ref=v1.42.0"
  nrn                                   = var.nrn
  k8s_provider                          = var.k8s_provider
  np_api_key                            = var.np_api_key
  gateway_enabled                       = true
  gateway_internal_enabled              = true
  tls_required                          = false
  gateway_public_aws_name               = "k8s-np-test-helm-public"
  gateway_internal_aws_name             = "k8s-np-test-helm-int"
  gateway_private_aws_security_group_id = module.base_security.private_gateway_security_group_id
  gateway_public_aws_security_group_id  = module.base_security.public_gateway_security_group_id
  gateway_use_cluster_ip                = true
  gateway_public_aws_dns_name           = data.aws_lb.public.dns_name
  gateway_private_aws_dns_name          = data.aws_lb.private.dns_name


  depends_on = [module.eks]
}


module "base_security" {
  source                     = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/security?ref=v1.42.0"
  cluster_name               = module.eks.eks_cluster_name
  gateway_internal_enabled   = true
  additional_network_cidrs   = ["100.17.0.0/16"]
  health_check_rules_enabled = false
  cluster_security_group_id  = data.aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id
  gateway_port               = 80
  vpc_id                     = "vpc-0a5dfe8e463dee15d"
}

###############################################################################
# Prometheus Config
################################################################################
module "nullplatform_prometheus" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/prometheus?ref=v1.42.0"

  depends_on = [module.eks]
}

module "agent" {
  source                  = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/agent?ref=v1.42.0"
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
  api_key                 = module.agent_api_key.api_key
  agent_repos_extra = ["https://${var.github_token}@github.com/pae-nullplatform/service.git#main"]


  depends_on = [module.eks]
}

module "scope_definition" {
  source                   = "git::https://github.com/nullplatform/tofu-modules.git///nullplatform/scope_definition?ref=v1.42.0"
  nrn                      = var.nrn
  np_api_key               = var.np_api_key
  service_spec_name        = "AgentScope"
  service_spec_description = "Deployments using agent scopes"

}

module "scope_definition_agent_association" {
  source                   = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition_agent_association?ref=v1.42.0"
  nrn                      = var.nrn
  tags_selectors           = var.tags_selectors
  api_key                  = module.scope_definition_agent_association_api_key.api_key
  scope_specification_id   = module.scope_definition.service_specification_id
  scope_specification_slug = module.scope_definition.service_slug
}

module "scope_definition_agent_association_api_key" {
  source             = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/api_key?ref=v1.42.0"
  type               = "scope_notification"
  nrn                = var.nrn
  specification_slug = "k8s"
}
###############################################################################
# Agent IAM
################################################################################

module "agent_iam" {
  source                              = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/aws/iam/agent?ref=v1.42.0"
  aws_iam_openid_connect_provider_arn = module.eks.eks_oidc_provider_arn

  agent_namespace = var.namespace
  cluster_name    = var.cluster_name
}

module "agent_api_key" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/api_key?ref=v1.42.0"
  type   = "agent"
  nrn    = var.nrn
}

module "istio" {
  source       = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/istio?ref=v1.42.0"
  service_type = "ClusterIP"

  depends_on = [module.eks]
}

module "external_dns_iam" {
  source                              = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/aws/iam/external_dns?ref=v1.42.0"
  aws_iam_openid_connect_provider_arn = module.eks.eks_oidc_provider_arn
  cluster_name                        = var.cluster_name
  hosted_zone_private_id              = module.dns.private_zone_id
  hosted_zone_public_id               = module.dns.public_zone_id
}

module "external_dns" {
  source            = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/external_dns?ref=v1.42.0"
  aws_region        = var.aws_region
  dns_provider_name = var.dns_provider_name
  domain_filters    = var.domain_name
  aws_iam_role_arn  = module.external_dns_iam.nullplatform_external_dns_role_arn
  zone_id_filter    = module.dns.public_zone_id
  zone_type         = "public"
  policy            = var.policy
  sources           = var.resources
  type              = "public"
  create_namespace  = true


  depends_on = [module.eks]
}

module "external_dns_private" {
  source            = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/external_dns?ref=v1.42.0"
  aws_region        = var.aws_region
  dns_provider_name = var.dns_provider_name
  domain_filters    = var.domain_name
  aws_iam_role_arn  = module.external_dns_iam.nullplatform_external_dns_role_arn
  zone_id_filter    = module.dns.private_zone_id
  zone_type         = "private"
  policy            = var.policy
  sources           = var.resources
  type              = "private"
  create_namespace  = false

  depends_on = [module.eks]
}

###############################################################################
# EKS Primary Security Group
###############################################################################
data "aws_eks_cluster" "this" {
  count = var.cluster_name != "" ? 1 : 0
  name  = module.eks.eks_cluster_name
}

###############################################################################
# ALB Data Sources - look up ALBs by name to get their DNS hostnames
# Used by Gateway annotations to configure external-dns targets.
###############################################################################
data "aws_lb" "public" {
  name = "${var.cluster_name}-public"
}

data "aws_lb" "private" {
  name = "${var.cluster_name}-private"
}

###############################################################################
# EKS Auto Mode — IngressClass for ALB
# Auto Mode includes the LB controller in the control plane but does NOT
# create the IngressClass automatically.  We must create it so that Ingress
# resources with ingressClassName: alb are reconciled.
# Ref: https://docs.aws.amazon.com/eks/latest/userguide/auto-configure-alb.html
###############################################################################
resource "kubernetes_ingress_class_v1" "alb" {
  metadata {
    name = "alb"
    labels = {
      "app.kubernetes.io/name" = "LoadBalancerController"
    }
  }

  spec {
    controller = "eks.amazonaws.com/alb"
  }

  depends_on = [module.eks]
}

###############################################################################
# Public ALB (internet-facing)
# - TLS termination via ACM
# - WAF attached
# - Security group from base_security module
# - Backend: Gateway API public gateway (auto-created by Istio)
###############################################################################
resource "kubernetes_ingress_v1" "alb_public" {
  metadata {
    name      = "gateway-alb-public"
    namespace = "gateways"
    annotations = {
      "alb.ingress.kubernetes.io/group.name"         = "k8s-np-test-helm-public"
      "alb.ingress.kubernetes.io/load-balancer-name" = "k8s-np-test-helm-public"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      "alb.ingress.kubernetes.io/listen-ports"       = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
      "alb.ingress.kubernetes.io/certificate-arn"    = module.acm.acm_certificate_arn
      "alb.ingress.kubernetes.io/wafv2-acl-arn"      = aws_wafv2_web_acl.main.arn
      "alb.ingress.kubernetes.io/security-groups"    = module.base_security.public_gateway_security_group_id
      "alb.ingress.kubernetes.io/healthcheck-port"   = "15021"
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/healthz/ready"
      # AUDIT: Deletion protection debe estar habilitado
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "deletion_protection.enabled=true"
      "alb.ingress.kubernetes.io/target-group-attributes"  = "deregistration_delay.timeout_seconds=10"
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "gateway-public-istio"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [module.eks]
}

###############################################################################
# Private ALB (internal)
# - TLS termination via ACM
# - WAF attached
# - Security group from base_security module
# - Backend: Gateway API private gateway (auto-created by Istio)
###############################################################################
resource "kubernetes_ingress_v1" "alb_private" {
  metadata {
    name      = "gateway-alb-private"
    namespace = "gateways"
    annotations = {
      "alb.ingress.kubernetes.io/group.name"         = "k8s-np-test-helm-int"
      "alb.ingress.kubernetes.io/load-balancer-name" = "k8s-np-test-helm-int"
      "alb.ingress.kubernetes.io/scheme"             = "internal"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      "alb.ingress.kubernetes.io/listen-ports"       = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
      "alb.ingress.kubernetes.io/certificate-arn"    = module.acm.acm_certificate_arn
      "alb.ingress.kubernetes.io/wafv2-acl-arn"      = aws_wafv2_web_acl.main.arn
      "alb.ingress.kubernetes.io/security-groups"    = module.base_security.private_gateway_security_group_id
      "alb.ingress.kubernetes.io/healthcheck-port"   = "15021"
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/healthz/ready"
      # AUDIT: Deletion protection debe estar habilitado
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "deletion_protection.enabled=true"
      "alb.ingress.kubernetes.io/target-group-attributes"  = "deregistration_delay.timeout_seconds=10"
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "gateway-private-istio"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [module.eks]
}



module "backend" {
  source        = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/backend?ref=v1.42.0"
  bucket_prefix = var.bucket_prefix
  aws_region    = var.aws_region
}

###############################################################################
# RDS Shared Infrastructure
# Subnet group and security group shared by all RDS instances managed by NP.
# Scripts discover these resources by the tag Purpose=nullplatform-rds.
###############################################################################

resource "aws_db_subnet_group" "nullplatform_rds" {
  name        = "${var.cluster_name}-rds"
  description = "Subnet group for NullPlatform-managed RDS instances"
  subnet_ids  = ["subnet-05070032ec080012a", "subnet-00c0bdda437e22490"]

  tags = {
    Name        = "${var.cluster_name}-rds"
    Purpose     = "nullplatform-rds"
    ManagedBy   = "nullplatform"
  }
}

resource "aws_security_group" "nullplatform_rds" {
  name        = "${var.cluster_name}-rds"
  description = "Security group for NullPlatform-managed RDS instances"
  vpc_id      = "vpc-0a5dfe8e463dee15d"

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.16.0.0/16"]
    description = "PostgreSQL access from within the VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.cluster_name}-rds"
    Purpose   = "nullplatform-rds"
    ManagedBy = "nullplatform"
  }
}

###############################################################################
# IAM: grant the NullPlatform agent permission to manage RDS and credentials
###############################################################################

resource "aws_iam_role_policy" "agent_rds" {
  name = "nullplatform-agent-rds"
  # Extract role name from the ARN (arn:aws:iam::ACCOUNT:role/ROLE_NAME)
  role = element(split("/", module.agent_iam.nullplatform_agent_role_arn), length(split("/", module.agent_iam.nullplatform_agent_role_arn)) - 1)

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RDSManagement"
        Effect = "Allow"
        Action = [
          "rds:CreateDBInstance",
          "rds:DeleteDBInstance",
          "rds:ModifyDBInstance",
          "rds:DescribeDBInstances",
          "rds:DescribeDBSubnetGroups",
          "rds:AddTagsToResource",
          "rds:ListTagsForResource",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerRDS"
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:TagResource"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:nullplatform/rds/*"
      },
      {
        Sid      = "SecretsManagerList"
        Effect   = "Allow"
        Action   = ["secretsmanager:ListSecrets"]
        Resource = "*"
      }
    ]
  })
}

###############################################################################
# RDS Service-Linked Role
# Required by AWS for RDS operations (subnet group discovery, instance mgmt).
###############################################################################
resource "aws_iam_service_linked_role" "rds" {
  aws_service_name = "rds.amazonaws.com"
}

###############################################################################
# RDS Postgres Service Definition
# Registers the service spec (+ link spec) from pae-nullplatform/service in NP.
###############################################################################

module "rds_postgres_service_definition" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_definition?ref=v1.42.0"

  nrn                 = var.nrn
  np_api_key          = var.np_api_key
  git_repo            = "pae-nullplatform/service"
  git_ref             = "main"
  git_service_path    = "databases/postgres/rds"
  service_name        = "RDS Postgres Server"
  service_description = "AWS RDS PostgreSQL managed instance"
}

module "rds_postgres_service_api_key" {
  source             = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/api_key?ref=v1.42.0"
  type               = "scope_notification"
  nrn                = var.nrn
  specification_slug = module.rds_postgres_service_definition.slug
}

module "rds_postgres_service_agent_association" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_definition_agent_association?ref=v1.42.0"

  nrn                        = var.nrn
  tags_selectors             = var.tags_selectors
  api_key                    = module.rds_postgres_service_api_key.api_key
  service_specification_id   = module.rds_postgres_service_definition.service_specification_id
  service_specification_slug = module.rds_postgres_service_definition.slug
  service_path = "databases/postgres/rds"
  agent_command = {
    type = "exec"
    data = {
      cmdline = "/root/.np/pae-nullplatform/service/databases/postgres/rds/handle-service-agent"
      environment = {
        NP_ACTION_CONTEXT = "$${NOTIFICATION_CONTEXT}"
      }
    }
  }

  depends_on = [module.agent]
}



