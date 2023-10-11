provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = module.eks.cluster_certificate_authority_data
    token                  = data.aws_eks_cluster_auth.main.token
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["token", "--cluster-id", module.eks.cluster_id]
      command     = "aws-iam-authenticator"
    }
  }
}
