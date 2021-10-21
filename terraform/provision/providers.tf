provider "aws" {
  # We need at least 3.31.0 because it was the first version to support DS
  # records in aws_route53_record
  version = "~> 3.31"
  region  = local.region
}

# A separate provider for creating KMS keys in the us-east-1 region, which is required for DNSSEC.
# See https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-configuring-dnssec-cmk-requirements.html
provider "aws" {
  alias   = "dnssec-key-provider"
  version = "~> 3.31"
  region  = "us-east-1"
}


provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token

  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    args        = ["token", "--cluster-id", data.aws_eks_cluster.main.id]
    command     = "aws-iam-authenticator"
  }
  version = "~>2.5"
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["token", "--cluster-id", data.aws_eks_cluster.main.id]
      command     = "aws-iam-authenticator"
    }
  }

  version = "~>2.3"
}

