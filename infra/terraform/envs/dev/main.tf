provider "aws" {
  region  = var.region
  profile = var.profile

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  name_prefix = "${var.project}-${var.environment}"
}

module "ecr" {
  source = "../../modules/ecr"

  name = "${var.project}-backend"
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  table_name = "${local.name_prefix}-articles"
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "dynamodb_table" {
  value = module.dynamodb.table_name
}
