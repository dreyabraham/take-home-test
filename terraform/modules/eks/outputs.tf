output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "API server endpoint of the EKS cluster"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_data" {
  description = "Base64 encoded certificate authority data"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "node_group_name" {
  description = "Name of the managed node group"
  value       = aws_eks_node_group.main.node_group_name
}
