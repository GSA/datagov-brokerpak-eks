output "domain_name" { value = local.domain }
output "host" { value = data.aws_eks_cluster.main.endpoint }
output "cluster_ca_certificate" { value = data.aws_eks_cluster.main.certificate_authority[0].data }
output "cluster-id" { value = data.aws_eks_cluster.main.id }
output "token" { 
  value = data.kubernetes_secret.secret.data.token
  description = "A cluster-admin token for use in constructing your own kubernetes configuration. NOTE: Do _not_ use this token when configuring the required_provider or you'll get a dependency cycle. Instead use exec with the same AWS credentials that were used for the required_providers aws provider."
}
output "admin_kubeconfig" { 
  value = data.template_file.admin_kubeconfig.rendered 
  description = "A kubeconfig for a cluster-admin service account."
}