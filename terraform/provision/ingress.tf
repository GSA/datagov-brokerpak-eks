locals {
  base_domain = var.zone
  domain      = "${local.subdomain}.${local.base_domain}"
  subdomain   = var.subdomain
}

# We need an OIDC provider for the ALB ingress controller to work
data "tls_certificate" "main" {
  url = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.main.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# Use a convenient module to install the AWS Load Balancer controller
module "aws_load_balancer_controller" {
  # source                    = "/local/path/to/terraform-kubernetes-aws-load-balancer-controller"
  source           = "github.com/GSA/terraform-kubernetes-aws-load-balancer-controller.git?ref=upgrade-v2"
  k8s_cluster_type = "eks"
  k8s_namespace    = "kube-system"
  aws_region_name  = data.aws_region.current.name
  k8s_cluster_name = data.aws_eks_cluster.main.name
  alb_controller_depends_on = [
    module.vpc,
    null_resource.cluster-functional,
  ]
  aws_tags = merge(var.labels, { "domain" = local.domain })
}

# ---------------------------------------------------------
# Provision the Ingress Controller using Helm
# ---------------------------------------------------------
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  chart      = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  version    = "3.37.0"

  namespace       = "kube-system"
  cleanup_on_fail = "true"
  atomic          = "true"
  timeout         = 600

  dynamic "set" {
    for_each = {
      "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"         = "internet-facing",
      "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ssl-ports"      = "https",
      "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ssl-cert"       = aws_acm_certificate.cert.arn,
      "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-nlb-target-type"= "ip"
      "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"           = "external",
      "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-proxy-protocol" = "*",
      # Enable this one everything else is working
      # "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-backend-protocol"     = "ssl"

      "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-name"           = local.subdomain,
      # "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-alpn-policy"    = "HTTP2Preferred",
      "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ssl-negotiation-policy" = "ELBSecurityPolicy-TLS-1-2-2017-01"
      # Enable this to restrict clients by CIDR range
      # "controller.service.annotations.service\\.beta\\.kubernetes\\.io/load-balancer-source-ranges"     = var.client-cidrs

      # Enable this to accept ipv6 connections (right now errors with "You must
      # specify subnets with an associated IPv6 CIDR block.")
      # "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ip-address-type"=
      # "dualstack",


      # TODO: AWS WAF doesn't work with NLBs. We probably have to set up Cloudfront in
      # front of the NLB in order to get that functionality back
      # "alb.ingress.kubernetes.io/wafv2-acl-arn"              = aws_wafv2_web_acl.waf_acl.arn
      "controller.service.externalTrafficPolicy"     = "Local",
      "controller.service.type"                      = "LoadBalancer",
      "controller.config.server-tokens"              = false,
      "controller.config.use-proxy-protocol"         = false,
      "controller.config.compute-full-forwarded-for" = true,
      "controller.config.use-forwarded-headers"      = true,
      "controller.metrics.enabled"                   = true,
      "controller.autoscaling.maxReplicas"           = 1,
      "controller.autoscaling.minReplicas"           = 1,
      "controller.autoscaling.enabled"               = true,
      "controller.publishService.enabled"            = false,
      "controller.extraArgs.publish-status-address"  = local.domain,
      "serviceAccount.create"                        = true,
      "rbac.create"                                  = true,
      "clusterName"                                  = module.eks.cluster_id,
      "region"                                       = local.region,
      "vpcId"                                        = module.vpc.vpc_id,
      "aws_iam_role_arn"                             = module.aws_load_balancer_controller.aws_iam_role_arn
    }
    content {
      name  = set.key
      value = set.value
    }
  }
  values = [<<-VALUES
    controller: 
      extraArgs: 
        http-port: 8080 
        https-port: 8543 
      containerPort: 
        http: 8080 
        https: 8543 
      service: 
        ports: 
          http: 80 
          https: 443 
        targetPorts: 
          http: 8080 
          https: 8543 
      image: 
        allowPrivilegeEscalation: false
    VALUES
  ]
  depends_on = [
    null_resource.cluster-functional,
    module.aws_load_balancer_controller
  ]
}

# Give the AWS LB controller time to react to any recent events (eg an ingress was
# removed and an ALB needs to be deleted) before actually removing it. Any
# Ingress or Service:LoadBalancer resource created in future should add this as
# a depends_on in order to ensure an orderly destroy!
resource "time_sleep" "alb_controller_destroy_delay" {
  depends_on       = [module.aws_load_balancer_controller]
  destroy_duration = "30s"
}


resource "aws_wafv2_web_acl" "waf_acl" {
  name        = "eks-${local.cluster_name}"
  description = "EKS WAF rule"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = {
      0 = "AWS-AWSManagedRulesCommonRuleSet",
      1 = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
      2 = "AWS-AWSManagedRulesSQLiRuleSet"
      3 = "AWS-AWSManagedRulesUnixRuleSet"
      4 = "AWS-AWSManagedRulesLinuxRuleSet"
      5 = "AWS-AWSManagedRulesAmazonIpReputationList"
    }
    content {
      priority = rule.key
      name     = rule.value

      override_action {
        count {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = element(split("-", rule.value), 0) # what's before the -
          name        = element(split("-", rule.value), 1) # what's after the -
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = false
        metric_name                = rule.value
        sampled_requests_enabled   = true
      }
    }
  }

  tags = {
    EKSCluster = local.cluster_name
  }
  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "eks-${local.cluster_name}"
    sampled_requests_enabled   = true
  }
}


# Create ACM certificate for the sub-domain
resource "aws_acm_certificate" "cert" {
  domain_name = local.domain
  # See https://www.terraform.io/docs/providers/aws/r/acm_certificate_validation.html#alternative-domains-dns-validation-with-route-53
  subject_alternative_names = [
    "*.${local.domain}"
  ]
  validation_method = "DNS"
  tags = merge(var.labels, {
    domain      = local.domain
    environment = local.cluster_name
  })
}

# Validate the certificate using DNS method
resource "aws_route53_record" "cert_validation" {
  name    = tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_type
  zone_id = aws_route53_zone.cluster.id
  records = [tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [aws_route53_record.cert_validation.fqdn]
}

data "kubernetes_service" "ingress_service" {
  metadata {
    name = "ingress-nginx-controller"
    namespace = "kube-system"
  }
  depends_on = [
    helm_release.ingress_nginx
  ]
}

# Create a local variable for the load balancer name.
locals {
  nlb_name = split("-", split(".", data.kubernetes_service.ingress_service.status.0.load_balancer.0.ingress.0.hostname).0).0
}

# Read information about the NLB created for the ingress service
data "aws_lb" "ingress_nlb" {
  name = local.nlb_name
}

# Create an A record in the subdomain zone aliased to the NLB
resource "aws_route53_record" "nlb" {
  zone_id = aws_route53_zone.cluster.id
  name    = local.domain
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress_nlb.dns_name
    zone_id                = data.aws_lb.ingress_nlb.zone_id
    evaluate_target_health = true
  }
}
