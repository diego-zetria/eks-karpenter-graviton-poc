# nacl.tf — Three-tier Network ACLs (defense-in-depth)
#
# Enforces network segmentation at the subnet level:
#   Public  → can reach Private (compute), BLOCKED from Database
#   Private → can reach Database on specific ports (5432, 6379)
#   Database → only accepts from Private, denies everything else
#
# NACLs are stateless — both inbound and outbound rules are required.

# =============================================================================
# Database (Secure) Tier — most restrictive
# Only accepts PostgreSQL (5432) and Redis (6379) from private compute subnets
# =============================================================================

resource "aws_network_acl" "database" {
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.database_subnets

  tags = merge(var.tags, { Name = "${var.cluster_name}-nacl-database" })
}

# Inbound: Allow PostgreSQL from each private (compute) subnet
resource "aws_network_acl_rule" "database_in_postgres" {
  count          = length(local.private_subnets)
  network_acl_id = aws_network_acl.database.id
  rule_number    = 100 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.private_subnets[count.index]
  from_port      = 5432
  to_port        = 5432
}

# Inbound: Allow Redis from each private (compute) subnet
resource "aws_network_acl_rule" "database_in_redis" {
  count          = length(local.private_subnets)
  network_acl_id = aws_network_acl.database.id
  rule_number    = 200 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.private_subnets[count.index]
  from_port      = 6379
  to_port        = 6379
}

# Outbound: Ephemeral return traffic to private subnets only
resource "aws_network_acl_rule" "database_out_ephemeral" {
  count          = length(local.private_subnets)
  network_acl_id = aws_network_acl.database.id
  rule_number    = 100 + count.index
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.private_subnets[count.index]
  from_port      = 1024
  to_port        = 65535
}

# All other traffic is denied by the implicit DENY rule (rule *)

# =============================================================================
# Public Tier — internet-facing (ALB, NAT Gateway)
# Explicitly blocks direct access to database subnets
# =============================================================================

resource "aws_network_acl" "public" {
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  tags = merge(var.tags, { Name = "${var.cluster_name}-nacl-public" })
}

# --- Inbound ---

resource "aws_network_acl_rule" "public_in_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "public_in_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

# Ephemeral return traffic (responses from internet, VPC, NAT)
resource "aws_network_acl_rule" "public_in_ephemeral" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# --- Outbound ---

# DENY all traffic to database subnets (evaluated before the allow-all)
resource "aws_network_acl_rule" "public_out_deny_database" {
  count          = length(local.database_subnets)
  network_acl_id = aws_network_acl.public.id
  rule_number    = 50 + count.index
  egress         = true
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = local.database_subnets[count.index]
  from_port      = 0
  to_port        = 0
}

# Allow all other outbound (to private subnets via ALB, to internet)
resource "aws_network_acl_rule" "public_out_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}

# =============================================================================
# Private (Compute) Tier — EKS nodes
# Can reach database on specific ports; all intra-VPC and NAT traffic allowed
# =============================================================================

resource "aws_network_acl" "private" {
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  tags = merge(var.tags, { Name = "${var.cluster_name}-nacl-private" })
}

# --- Inbound ---

# Allow all intra-VPC traffic (ALB → pods, pod-to-pod, EKS control plane)
resource "aws_network_acl_rule" "private_in_vpc" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 0
  to_port        = 0
}

# Ephemeral return traffic from internet (via NAT Gateway)
resource "aws_network_acl_rule" "private_in_ephemeral" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# --- Outbound ---

# Allow all outbound (database access, NAT gateway, EKS API, etc.)
# Database-side NACL enforces port restrictions (defense-in-depth)
resource "aws_network_acl_rule" "private_out_all" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 0
  to_port        = 0
}
