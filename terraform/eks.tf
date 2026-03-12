module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Networking
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Cluster access
  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  # EKS Addons
  addons = {
    coredns = {
      configuration_values = jsonencode({
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }]
      })
    }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
  }

  # Managed node group for Karpenter controller
  # Uses Graviton (ARM64) for cost savings — even system nodes are optimized
  eks_managed_node_groups = {
    karpenter = {
      ami_type       = "AL2023_ARM_64_STANDARD"
      instance_types = ["m7g.medium"]
      capacity_type  = "ON_DEMAND"

      min_size     = 1
      max_size     = 3
      desired_size = 2

      labels = {
        "karpenter.sh/controller" = "true"
      }

      taints = {
        karpenter = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # Tag node security group for Karpenter discovery
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = var.tags
}
