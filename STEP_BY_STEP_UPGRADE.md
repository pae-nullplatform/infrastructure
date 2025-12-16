# Step by Step - Upgrade Nullplatform Agent con Istio y External Authorization

Este documento describe el proceso paso a paso para actualizar la infraestructura de nullplatform, incluyendo la migracion a Istio y la configuracion de autorizacion externa con OPA.

## Pre-requisitos

- OpenTofu/Terraform instalado
- kubectl configurado con acceso al cluster EKS
- AWS CLI configurado con el perfil correcto (`aws-profile: providers-test`)
- Acceso al repositorio de modulos de nullplatform

---

## Paso 1: Comentar o Eliminar el modulo foundations_networking

Editar el archivo `main.tf` y comentar o eliminar el modulo `foundations_networking`:

```hcl
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
```

> **Nota:** Este modulo se reemplaza por la configuracion de Istio Gateway que se agregara mas adelante.

---

## Paso 2: Destroy del modulo nullplatform_scope_agent

Ejecutar el destroy especifico del modulo `nullplatform_scope_agent`:

```bash
tofu destroy -target=module.nullplatform_scope_agent
```

Confirmar la destruccion cuando se solicite.

> **Importante:** Este paso es necesario para poder actualizar la version del modulo y agregar las nuevas variables sin conflictos.

---

## Paso 3: Actualizar el modulo nullplatform_scope_agent

### 3.1 Actualizar version a 1.12.4 y agregar nuevas variables

Modificar el bloque del modulo `nullplatform_scope_agent` en `main.tf`:

```hcl
module "nullplatform_scope_agent" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/agent?ref=v1.12.4"

  cluster_name                        = module.foundations_eks.eks_cluster_name
  nrn                                 = var.nrn
  tags_selectors                      = var.tags_selectors
  cloud_provider                      = var.cluster_provider
  image_tag                           = var.image_tag
  aws_iam_role_arn                    = module.agent_iam.nullplatform_agent_role_arn
  extra_config                        = var.extra_config
}
```

### 3.2 Agregar el modulo scope_definition

```hcl
module "scope_definition" {
  source                              = "git::https://github.com/nullplatform/tofu-modules.git///nullplatform/scope_definition?ref=v1.12.3"
  nrn                                 = var.nrn
  np_api_key                          = var.np_api_key
  service_spec_name                   = "AgentScope"
  service_spec_description            = "Deployments using agent scopes"
}
```

### 3.3 Agregar el modulo scope_definition_agent_association

```hcl
module "scope_definition_agent_association" {
  source                     = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/scope_definition_agent_association?ref=v1.12.3"
  nrn                        = var.nrn
  np_api_key                 = var.np_api_key
  service_specification_id   = module.scope_definition.service_specification_id
  service_specification_slug = module.scope_definition.service_slug
  tags_selectors             = var.tags_selectors
}
```

### 3.4 Agregar el modulo agent_iam

```hcl
###############################################################################
# Agent IAM
################################################################################
module "agent_iam" {
  source                              = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/aws/iam?ref=v1.12.4"
  aws_iam_openid_connect_provider_arn = module.foundations_eks.eks_oidc_provider_arn

  agent_namespace = var.namespace
  cluster_name    = var.cluster_name
}
```

### 3.5 Agregar el modulo istio

```hcl
module "istio" {
  source = "git::https://github.com/nullplatform/tofu-modules.git///infrastructure/commons/istio?ref=v1.12.3"
}
```

### 3.6 Agregar variables en variables.tf

Agregar las siguientes variables al archivo `variables.tf`:

```hcl
variable "cluster_provider" {}
variable "image_tag" {}
variable "extra_config" {}
```

### 3.7 Agregar valores en terraform.tfvars

Agregar los siguientes valores al archivo `terraform.tfvars`:

```hcl
image_tag        = "aws"
cluster_provider = "aws"

extra_config = {
  SERVICE_TEMPLATE        = "/root/.np/nullplatform/scopes/k8s/deployment/templates/istio/service.yaml.tpl"
  INITIAL_INGRESS_PATH    = "/root/.np/nullplatform/scopes/k8s/deployment/templates/istio/initial-httproute.yaml.tpl"
  BLUE_GREEN_INGRESS_PATH = "/root/.np/nullplatform/scopes/k8s/deployment/templates/istio/blue-green-httproute.yaml.tpl"
}
```

### 3.8 Ejecutar Plan & Apply

```bash
tofu plan
tofu apply
```

Verificar que todos los recursos se creen correctamente antes de continuar.

---

## Paso 4: Crear Namespaces y Gateway

### 4.1 Crear namespace nullplatform (si no existe)

Agregar en `main.tf`:

```hcl
resource "kubernetes_namespace_v1" "nullplatform" {
  metadata {
    name = "nullplatform"
  }
}
```

### 4.2 Crear namespace gateway

Agregar en `main.tf`:

```hcl
resource "kubernetes_namespace_v1" "gateway" {
  metadata {
    name = "gateways"
  }
}
```

### 4.3 Crear recurso Gateway

Agregar en `main.tf`:

```hcl
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
```

### 4.4 Ejecutar Plan & Apply

```bash
tofu plan
tofu apply
```

---

## Paso 5: Agregar AuthorizationPolicy

### 5.1 Agregar recurso de policy

Agregar en `main.tf`:

```hcl
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
```

### 5.2 Ejecutar Plan & Apply

```bash
tofu plan
tofu apply
```

---

## Paso 6: Desplegar OPA External Authorization

Aplicar el manifiesto `opa-ext-authz.yaml` que contiene:
- ConfigMap con las politicas OPA (validacion de JWT)
- Deployment de OPA con imagen `openpolicyagent/opa:0.60.0-envoy`
- Service para exponer OPA

```bash
kubectl apply -f opa-ext-authz.yaml
```

Verificar que los pods esten corriendo:

```bash
kubectl get pods -n gateway -l app=opa-ext-authz
```

---

## Paso 7: Desplegar Pod de Test

### 7.1 Modificar el hostname en pod-test.yaml

Antes de aplicar, modificar el archivo `pod-test.yaml` y actualizar el hostname con el DNS correcto:

```yaml
# En la seccion HTTPRoute, modificar:
spec:
  hostnames:
    - "hello.<TU_DOMINIO>"  # Ejemplo: hello.pae-infra.nullapps.io
```

Para el dominio actual (`pae-infra.nullapps.io`):

```yaml
spec:
  hostnames:
    - "hello.pae-infra.nullapps.io"
```

### 7.2 Aplicar el manifiesto

```bash
kubectl apply -f pod-test.yaml
```

Verificar que los recursos se crearon:

```bash
kubectl get pods -n nullplatform -l app=nginx-hello
kubectl get svc -n nullplatform
kubectl get httproute -n nullplatform
```

---

## Paso 8: Validacion

### 8.1 Probar endpoint sin autorizacion (/)

Acceder a la URL raiz deberia mostrar "Hello World":

```bash
curl -k https://hello.pae-infra.nullapps.io/
```

**Resultado esperado:** Pagina HTML con "Hello World!"

### 8.2 Probar endpoint protegido (/smoke)

Acceder al path `/smoke` sin token deberia retornar 401:

```bash
curl -k https://hello.pae-infra.nullapps.io/smoke
```

**Resultado esperado:** HTTP 401 - Authorization required

### 8.3 Probar con JWT valido

Para probar con un JWT valido, usar las herramientas de Istio:
- Repositorio: https://github.com/istio/istio/tree/master/security/tools/jwt

Usar el token "sample" con el scope `foo: bar` (security/tools/jwt/samples/demo.jwt)

Probar con el token:

```bash
TOKEN="<TU_JWT_TOKEN>"
curl -k -H "Authorization: Bearer $TOKEN" https://hello.pae-infra.nullapps.io/smoke
```

**Resultado esperado con token valido:** Pagina HTML con "Hello Smoke"

---

## Resumen de Archivos Modificados

| Archivo | Cambios |
|---------|---------|
| `main.tf` | Comentar `foundations_networking`, actualizar `nullplatform_scope_agent` a v1.12.4, agregar modulos `scope_definition`, `scope_definition_agent_association`, `agent_iam`, `istio`, namespaces, gateway y policy |
| `variables.tf` | Agregar `cluster_provider`, `image_tag`, `extra_config` |
| `terraform.tfvars` | Agregar valores para las nuevas variables |

## Archivos YAML a Aplicar con kubectl

| Archivo | Descripcion |
|---------|-------------|
| `opa-ext-authz.yaml` | ConfigMap, Deployment y Service de OPA |
| `pod-test.yaml` | ConfigMap, Pod, Service y HTTPRoute de nginx para pruebas |

---

## Estructura de Validacion JWT

La politica OPA configurada valida:

1. **Presencia del token:** Header `Authorization: Bearer <token>`
2. **Validez del token:** Firma verificada con JWKS configurado
3. **Issuer correcto:** `iss: testing@secure.istio.io`
4. **Expiracion:** Token no expirado (`exp > now`)
5. **Claims requeridos:** `foo: bar`
6. **Metodos permitidos:** GET, POST

---

## Troubleshooting

### Verificar logs de OPA

```bash
kubectl logs -n gateway -l app=opa-ext-authz -f
```

### Verificar estado del Gateway

```bash
kubectl get gateway -n gateway
kubectl describe gateway gateway-public -n gateway
```

### Verificar AuthorizationPolicy

```bash
kubectl get authorizationpolicy -n gateway
kubectl describe authorizationpolicy ext-authz-smoke -n gateway
```

### Verificar que el extensionProvider este configurado

El modulo de Istio debe configurar el extensionProvider `opa-ext-authz` en el mesh config de Istio. Verificar con:

```bash
kubectl get configmap istio -n istio-system -o yaml | grep -A 20 extensionProviders
```
