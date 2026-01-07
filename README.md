# Infrastructure - AWS EKS Platform

Este directorio contiene la infraestructura base para desplegar un cluster EKS con todos los componentes necesarios para ejecutar aplicaciones en nullplatform.

## Arquitectura de Red

```
                          +----------------------------------+
                          |            AWS Cloud             |
                          |          <aws-region>            |
                          +----------------------------------+
                                         |
            +----------------------------+
            |                            |
            v                            v
    +---------------+           +----------------+
    |   Route 53    |           |   Route 53     |
    | Public Zone   |           | Private Zone   |
    | *.<domain>    |           | *.internal     |
    +---------------+           +----------------+
            |                            |
            +----------------------------+
                                         |
                                         v
                          +----------------------------------+
                          |              VPC                 |
                          |         10.0.0.0/16              |
                          +----------------------------------+
                                         |
            +----------------------------+----------------------------+
            |                                                         |
            v                                                         v
    +------------------+                                    +------------------+
    |  Public Subnets  |                                    | Private Subnets  |
    |  10.0.1.0/24     |                                    |  10.0.10.0/24    |
    |  10.0.2.0/24     |                                    |  10.0.11.0/24    |
    |  10.0.3.0/24     |                                    |  10.0.12.0/24    |
    +--------+---------+                                    +--------+---------+
             |                                                       |
             v                                                       v
    +------------------+                                    +------------------+
    |   NAT Gateway    |                                    |   EKS Cluster    |
    |   (Internet)     |<-----------------------------------| (<cluster-name>) |
    +------------------+                                    +------------------+
```

## Arquitectura del Cluster EKS

```
+------------------------------------------------------------------+
|                         EKS Cluster                               |
|                      (<cluster-name>)                             |
+------------------------------------------------------------------+
|                                                                   |
|  +------------------+  +------------------+  +------------------+ |
|  |  istio-system    |  |    gateways      |  |   nullplatform   | |
|  +------------------+  +------------------+  +------------------+ |
|  |                  |  |                  |  |                  | |
|  | - istiod         |  | - gateway-public |  | - nginx-hello    | |
|  | - istio-ingress  |  | - avp-ext-authz  |  | - applications   | |
|  |                  |  |                  |  |                  | |
|  +------------------+  +------------------+  +------------------+ |
|                                                                   |
|  +------------------+  +------------------+  +------------------+ |
|  |  cert-manager    |  |  external-dns    |  |   kube-system    | |
|  +------------------+  +------------------+  +------------------+ |
|  |                  |  |                  |  |                  | |
|  | - cert-manager   |  | - external-dns   |  | - aws-lb-ctrl    | |
|  | - ClusterIssuers |  |                  |  | - coredns        | |
|  |                  |  |                  |  |                  | |
|  +------------------+  +------------------+  +------------------+ |
|                                                                   |
+------------------------------------------------------------------+
```

## Modulos Terraform

### VPC (`module.vpc`)

Crea la red base con subnets publicas y privadas.

```hcl
module "vpc" {
  source       = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/vpc"
  account      = var.account
  organization = var.organization
  vpc          = var.vpc
}
```

**Recursos creados:**
- VPC con CIDR configurable
- 3 subnets publicas (una por AZ)
- 3 subnets privadas (una por AZ)
- Internet Gateway
- NAT Gateway
- Route Tables

### EKS (`module.eks`)

Cluster Kubernetes gestionado con EKS Auto Mode.

```hcl
module "eks" {
  source                  = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/eks"
  aws_subnets_private_ids = module.vpc.private_subnets
  aws_vpc_vpc_id          = module.vpc.vpc_id
  name                    = var.cluster_name
  use_auto_mode           = true
}
```

**Caracteristicas:**
- EKS Auto Mode habilitado
- Nodos gestionados automaticamente
- OIDC Provider para IRSA
- Encryption at rest

### DNS (`module.dns`)

Hosted zones para DNS publico y privado.

```hcl
module "dns" {
  source      = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/route53"
  domain_name = var.domain_name
  vpc_id      = module.vpc.vpc_id
}
```

**Recursos:**
- Public Hosted Zone (`*.<domain_name>`)
- Private Hosted Zone (`*.internal`)

### ALB Controller (`module.alb_controller`)

AWS Load Balancer Controller para crear ALBs automaticamente.

```hcl
module "alb_controller" {
  source                          = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/aws/alb_controller"
  aws_iam_openid_connect_provider = module.eks.eks_oidc_provider_arn
  cluster_name                    = module.eks.eks_cluster_name
  vpc_id                          = module.vpc.vpc_id
}
```

### Istio (`module.istio`)

Service mesh con soporte para Gateway API.

```hcl
module "istio" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/istio"
  depends_on = [module.eks, module.alb_controller]
}
```

**Componentes instalados:**
- Istio Base
- Istiod (control plane)
- Istio Ingress Gateway
- Gateway API CRDs

### External DNS (`module.external_dns`)

Sincroniza automaticamente registros DNS con servicios de Kubernetes.

```hcl
module "external_dns" {
  source                 = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/external_dns"
  aws_region             = var.aws_region
  domain_filters         = var.domain_name
  aws_iam_role_arn       = module.external_dns_iam.nullplatform_external_dns_role_arn
}
```

### Cert Manager (`module.cert_manager`)

Gestion automatica de certificados TLS con Let's Encrypt.

```hcl
module "cert_manager" {
  source              = "git::https://github.com/nullplatform/tofu-modules.git//infrastructure/commons/cert_manager"
  aws_region          = var.aws_region
  cloud_provider      = "aws"
  hosted_zone_name    = module.dns.public_zone_name
}
```

## Flujo de Trafico

```
        Internet
            |
            v
    +---------------+
    |  Route 53     |
    |  DNS Query    |
    +-------+-------+
            |
            v
    +---------------+
    |   AWS ALB     |
    | (HTTPS:443)   |
    +-------+-------+
            |
            v
    +---------------+
    | Istio Gateway |
    | (gateway-     |
    |  public)      |
    +-------+-------+
            |
            | HTTPRoute
            v
    +---------------+
    |  Service      |
    | (ClusterIP)   |
    +-------+-------+
            |
            v
    +---------------+
    |     Pod       |
    | (Application) |
    +---------------+
```

## Variables de Configuracion

| Variable | Descripcion |
|----------|-------------|
| `account` | Nombre de la cuenta |
| `organization` | Organizacion |
| `cluster_name` | Nombre del cluster EKS |
| `domain_name` | Dominio base para DNS |
| `aws_region` | Region de AWS |
| `aws_profile` | Perfil de AWS CLI |
| `np_api_key` | API Key de nullplatform |
| `nrn` | NRN de nullplatform |
| `tags_selectors` | Tags para seleccionar recursos |
| `vpc` | Configuracion de VPC (azs, cidr, subnets) |
| `github_installation_id` | ID de instalacion de GitHub App |
| `github_organization` | Organizacion de GitHub |
| `namespace` | Namespace de Kubernetes para tools |
| `image_tag` | Tag de imagen del agente |
| `cloud_provider` | Proveedor de nube |
| `dns_type` | Tipo de DNS |
| `use_account_slug` | Usar slug de cuenta |
| `image_pull_secrets` | Secretos para pull de imagenes |
| `service_template` | Path al template de servicio Istio |
| `initial_ingress_path` | Path al template de ingress inicial |
| `blue_green_ingress_path` | Path al template de ingress blue-green |
| `k8s_provider` | Proveedor de Kubernetes |
| `dns_provider_name` | Nombre del proveedor DNS |
| `policy` | Politica de External DNS |
| `resources` | Recursos para External DNS |

## Comandos Utiles

```bash
# Conectar al cluster
aws eks update-kubeconfig --region <aws-region> --name <cluster-name> --profile <aws-profile>

# Ver pods en todos los namespaces
kubectl get pods -A

# Ver gateways
kubectl get gateway -A

# Ver HTTPRoutes
kubectl get httproute -A

# Ver servicios con LoadBalancer
kubectl get svc -A | grep LoadBalancer

# Logs de Istio
kubectl logs -n istio-system -l app=istiod

# Logs de External DNS
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
```

## Outputs

| Output | Descripcion |
|--------|-------------|
| `eks_cluster_name` | Nombre del cluster EKS |
| `eks_cluster_endpoint` | Endpoint del API server |
| `vpc_id` | ID de la VPC |
| `private_subnets` | IDs de subnets privadas |
| `public_zone_id` | ID de la hosted zone publica |

## Troubleshooting

### Error: No se puede conectar al cluster

```bash
# Verificar contexto actual
kubectl config current-context

# Actualizar kubeconfig
aws eks update-kubeconfig --region <aws-region> --name <cluster-name> --profile <aws-profile>
```

### Error: Pods en Pending

```bash
# Verificar nodos disponibles
kubectl get nodes

# Ver eventos del pod
kubectl describe pod <pod-name> -n <namespace>
```

### Error: Certificate not ready

```bash
# Ver estado del certificado
kubectl get certificate -A

# Ver logs de cert-manager
kubectl logs -n cert-manager -l app=cert-manager
```
