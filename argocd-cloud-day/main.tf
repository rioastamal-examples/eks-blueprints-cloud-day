data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

################################################################################
# Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.16"

  cluster_name                   = local.name
  cluster_version                = "1.27"
  cluster_endpoint_public_access = true

  # EKS Addons
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  
  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      # arn:aws:iam::620092321600:user/demo
      rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${local.console_user}"
      username = "demo"
      groups   = ["system:masters"]
    }
  ]

  # We are using managed nodes, meaning the lifecycle of the EC2 is handled by EKS
  eks_managed_node_groups = {
    initial = {
      instance_types = ["m5.large"]

      min_size     = 3
      max_size     = 10
      desired_size = 5
    }
  }

  tags = local.tags
}

################################################################################
# Platform team configuration (Admin access)
################################################################################
module "eks_blueprints_admin_team" {
  source  = "aws-ia/eks-blueprints-teams/aws"
  version = "~> 1.0"

  name = "team-admin"

  enable_admin = true
  users        = [data.aws_caller_identity.current.arn]
  cluster_arn  = module.eks.cluster_arn

  tags = local.tags
}

################################################################################
# Application team configuration
################################################################################
module "eks_blueprints_team_jkt" {
  source  = "aws-ia/eks-blueprints-teams/aws"
  version = "~> 1.0"

  name = "team-jkt"

  users             = [data.aws_caller_identity.current.arn]
  cluster_arn       = module.eks.cluster_arn
  oidc_provider_arn = module.eks.oidc_provider_arn

  labels = {
    team = "team-jkt"
    project = "cloud-day"
  }

  annotations = {
    team = "team-jkt"
  }

  namespaces = {
    "team-jkt" = {
      labels = {
        appName     = "cloud-day-app",
        projectName = "jkt-cloud-day",
      }

      resource_quota = {
        hard = {
          "requests.cpu"    = "2000m",
          "requests.memory" = "4Gi",
          "limits.cpu"      = "4000m",
          "limits.memory"   = "16Gi",
          "pods"            = "20",
          "secrets"         = "20",
          "services"        = "20"
        }
      }
    } // jkt
  }

  tags = local.tags
}

################################################################################
# EKS Blueprints Addons
################################################################################
module "eks_blueprints_addons" {
  depends_on = [module.eks_blueprints_team_jkt]
  
  # Users should pin the version to the latest available release
  # tflint-ignore: terraform_module_pinned_source
  source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=blueprints-workshops/modules/kubernetes-addons"

  eks_cluster_id        = module.eks.cluster_name
  eks_cluster_endpoint  = module.eks.cluster_endpoint
  eks_cluster_version   = module.eks.cluster_version
  eks_oidc_provider     = module.eks.oidc_provider
  eks_oidc_provider_arn = module.eks.oidc_provider_arn

  enable_argocd = true
  # This example shows how to set default ArgoCD Admin Password using SecretsManager with Helm Chart set_sensitive values.
  argocd_helm_config = {
    set_sensitive = [
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt_hash.argo.id
      }
    ]
    set = [
      {
        name  = "server.service.type"
        value = "LoadBalancer"
      }
    ]
  }

  argocd_manage_add_ons = true # Indicates that ArgoCD is responsible for managing/deploying add-ons
  argocd_applications = {
    addons = {
      path               = "chart"
      repo_url           = "https://github.com/aws-samples/eks-blueprints-add-ons.git"
      add_on_application = true
    }
    # Activate this when all has been deployed
    # workloads = {
    #   path               = "envs/dev"
    #   repo_url           = "https://github.com/rioastamal-examples/eks-blueprints-workloads.git"
    #   add_on_application = false
    # }
  }

  # Add-ons
  enable_amazon_eks_aws_ebs_csi_driver = true
  enable_aws_load_balancer_controller  = true
  enable_cert_manager                  = true
  enable_karpenter                     = false
  enable_metrics_server                = true
  enable_argo_rollouts                 = true

  tags = local.tags
}

#---------------------------------------------------------------
# ArgoCD Admin Password credentials with Secrets Manager
# Login to AWS Secrets manager with the same role as Terraform to extract the ArgoCD admin password with the secret name as "argocd"
#---------------------------------------------------------------
resource "random_password" "argocd" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Argo requires the password to be bcrypt, we use custom provider of bcrypt,
# as the default bcrypt function generates diff for each terraform plan
resource "bcrypt_hash" "argo" {
  cleartext = random_password.argocd.result
}

#tfsec:ignore:aws-ssm-secret-use-customer-key
resource "aws_secretsmanager_secret" "argocd" {
  name                    = "argocd"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
}

resource "aws_secretsmanager_secret_version" "argocd" {
  secret_id     = aws_secretsmanager_secret.argocd.id
  secret_string = random_password.argocd.result
}