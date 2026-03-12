variable "region" {
  description = "AWS region for the EKS cluster"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "opsfleet-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project   = "opsfleet-tech-assignment"
    ManagedBy = "terraform"
  }
}
