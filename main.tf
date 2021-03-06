provider "kubernetes" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_blueprints.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
  }
}

module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.2.1"

  cluster_name    = local.name

  # EKS Cluster VPC and Subnet mandatory config
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  # EKS CONTROL PLANE VARIABLES
  cluster_version = local.cluster_version

  # List of map_roles
  map_roles          = [
    {
      rolearn  ="arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/demo3"     # The ARN of the IAM role
      username = "ops-role"                                           # The user name within Kubernetes to map to the IAM role
      groups   = ["system:masters"]                                   # A list of groups within Kubernetes to which the role is mapped; Checkout K8s Role and Rolebindings
    }
  ]

  # EKS MANAGED NODE GROUPS
  managed_node_groups = {
    mg_5 = {
      node_group_name = local.node_group_name
      instance_types  = ["m5.xlarge"]
      subnet_ids      = module.vpc.private_subnets
    }
  }

  platform_teams = {
    admin = {
      users = [
        data.aws_caller_identity.current.arn
      ]
    }
  }

  application_teams = {
    team-riker = {
      "labels" = {
        "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
        "appName"     = "riker-team-app",
        "projectName" = "project-riker",
        "environment" = "dev",
        "domain"      = "example",
        "uuid"        = "example",
        "billingCode" = "example",
        "branch"      = "example"
      }
      "quota" = {
        "requests.cpu"    = "10000m",
        "requests.memory" = "20Gi",
        "limits.cpu"      = "20000m",
        "limits.memory"   = "50Gi",
        "pods"            = "10",
        "secrets"         = "10",
        "services"        = "10"
      }
      ## Manifests Example: we can specify a directory with kubernetes manifests that can be automatically applied in the team-riker namespace.
      # manifests_dir = "./manifests-team-red"
      users         = [data.aws_caller_identity.current.arn]
    }


    ecsdemo-frontend = {
      "labels" = {
        "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
        "appName"     = "ecsdemo-frontend-app",
        "projectName" = "ecsdemo-frontend",
        "environment" = "dev",
      }
      #don't use quotas here cause ecsdemo app does not have request/limits 
      "quota" = {
        "requests.cpu"    = "10000m",
        "requests.memory" = "20Gi",
        "limits.cpu"      = "20000m",
        "limits.memory"   = "50Gi",
        "pods"            = "10",
        "secrets"         = "10",
        "services"        = "10"
      }
      ## Manifests Example: we can specify a directory with kubernetes manifests that can be automatically applied in the team-riker namespace.
      # manifests_dir = "./manifests-team-red"
      users         = [data.aws_caller_identity.current.arn]
    }
  }


  tags = local.tags
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  #version = "v3.2.0"
  version = "~> 3.0"

  name = local.name
  cidr = local.vpc_cidr

  azs  = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  create_igw           = true
  enable_dns_hostnames = true
  single_nat_gateway   = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }  

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = "1"
  }

    tags = local.tags
}

module "aws_controllers" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.2.1/modules/kubernetes-addons"

  eks_cluster_id = module.eks_blueprints.eks_cluster_id

  #---------------------------------------------------------------
  # Use AWS controllers separately
  # So that it can delete ressources it created from other addons or workloads
  #---------------------------------------------------------------

  enable_aws_load_balancer_controller = true
  enable_karpenter                    = true # Fail is put
  enable_aws_for_fluentbit            = false

  #depends_on = [module.eks_blueprints.managed_node_groups,module.kubernetes-addons]
  #depends_on = [module.eks_blueprints.managed_node_groups]
}


# Add the following to the bottom of main.tf

module "kubernetes-addons" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.2.1/modules/kubernetes-addons"

  eks_cluster_id = module.eks_blueprints.eks_cluster_id

  #---------------------------------------------------------------
  # ARGO CD ADD-ON
  #---------------------------------------------------------------

  enable_argocd         = true
  argocd_manage_add_ons = true # Indicates that ArgoCD is responsible for managing/deploying Add-ons.

  argocd_applications = {
    addons    = local.addon_application
    workloads = local.workload_application
    ecsdemo   = local.ecsdemo_application
  }

  argocd_helm_config = {
    values = [templatefile("${path.module}/argocd-values.yaml", {})]
  }

  #---------------------------------------------------------------
  # ADD-ONS - You can add additional addons here
  # https://aws-ia.github.io/terraform-aws-eks-blueprints/add-ons/
  #---------------------------------------------------------------

  enable_aws_for_fluentbit            = false
  enable_cert_manager                 = false
  enable_cluster_autoscaler           = false
  enable_ingress_nginx                = false
  enable_keda                         = false
  enable_metrics_server               = true
  enable_prometheus                   = false
  enable_traefik                      = false
  enable_vpa                          = true
  enable_yunikorn                     = false
  enable_argo_rollouts                = false

  #depends_on = [module.eks_blueprints.managed_node_groups,module.aws_controllers]
  #depends_on = [module.eks_blueprints.managed_node_groups]
}

# -----------
# Karpenter
# -----------

# resource "aws_iam_instance_profile" "karpenter" {
#   name = "karpenter"
#   role = aws_iam_role.role.name
# }

# resource "aws_iam_role" "role" {
#   name = "karpenter"
#   path = "/"

#   assume_role_policy = <<EOF
# {
#     "Version": "2012-10-17",
#     "Statement": [
#         {
#             "Action": "sts:AssumeRole",
#             "Principal": {
#                "Service": "ec2.amazonaws.com"
#             },
#             "Effect": "Allow",
#             "Sid": ""
#         }
#     ]
# }
# EOF
# }

# resource "aws_iam_role_policy" "karpenter_policy" {
#   name = "test_policy"
#   role = aws_iam_role.test_role.id

#   # Terraform's "jsonencode" function converts a
#   # Terraform expression result to valid JSON syntax.
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = [
#           "ec2:Describe*",
#         ]
#         Effect   = "Allow"
#         Resource = "*"
#       },
#     ]
#   })
# }

# Creates Launch templates for Karpenter
# Launch template outputs will be used in Karpenter Provisioners yaml files. Checkout this examples/karpenter/provisioners/default_provisioner_with_launch_templates.yaml
# module "karpenter_launch_templates" {
#   source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.2.1/modules/launch-templates"

#   eks_cluster_id = module.eks_blueprints.eks_cluster_id

#   launch_template_config = {
#     linux = {
#       ami                    = data.aws_ami.eks.id
#       launch_template_prefix = "karpenter"
#       iam_instance_profile   = module.eks_blueprints.managed_node_group_iam_instance_profile_id[0]
#       vpc_security_group_ids = [module.eks_blueprints.worker_node_security_group_id]
#       block_device_mappings = [
#         {
#           device_name = "/dev/xvda"
#           volume_type = "gp3"
#           volume_size = 200
#         }
#       ]
#     }

#     bottlerocket = {
#       ami                    = data.aws_ami.bottlerocket.id
#       launch_template_os     = "bottlerocket"
#       launch_template_prefix = "bottle"
#       iam_instance_profile   = module.eks_blueprints.managed_node_group_iam_instance_profile_id[0]
#       vpc_security_group_ids = [module.eks_blueprints.worker_node_security_group_id]
#       block_device_mappings = [
#         {
#           device_name = "/dev/xvda"
#           volume_type = "gp3"
#           volume_size = 200
#         }
#       ]
#     }
#   }

#  tags = merge(local.tags, { Name = "karpenter" })
#}


data "aws_ami" "eks" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-${module.eks_blueprints.eks_cluster_version}-*"]
  }
}

data "aws_ami" "bottlerocket" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["bottlerocket-aws-k8s-${module.eks_blueprints.eks_cluster_version}-x86_64-*"]
  }
}

data "kubectl_path_documents" "karpenter_provisioners" {
  pattern = "${path.module}/karpenter-provisioner.yaml"
  #pattern = "${path.module}/provisioners/*.yaml"
  vars = {
    azs                     = join(",", local.azs)
    iam-instance-profile-id = "${local.name}-${local.node_group_name}"
    eks-cluster-id          = local.name
    eks-vpc_name            = local.name
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
 for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
 yaml_body = each.value

 #depends_on = [module.aws_controllers]
}
