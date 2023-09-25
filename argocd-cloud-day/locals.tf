locals {
  name   = basename(path.cwd)
  region = "ap-southeast-1"
  console_user = "demo"

  # Spread across 3 AZs
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}