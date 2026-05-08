aws_region   = "us-east-1"
project_name = "myapp"
environment  = "prod"

# Networking
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# EKS
eks_cluster_version       = "1.29"
node_group_instance_types = ["t3.medium"]
node_group_desired_size   = 2
node_group_min_size       = 1
node_group_max_size       = 4

# ECR
ecr_repositories          = ["myapp-api", "myapp-worker"]
ecr_image_retention_count = 10
