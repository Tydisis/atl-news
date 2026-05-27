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
  image_uri   = "${module.ecr.repository_url}:${var.image_tag}"
}

module "ecr" {
  source = "../../modules/ecr"
  name   = "${var.project}-backend"
}

module "dynamodb" {
  source     = "../../modules/dynamodb"
  table_name = "${local.name_prefix}-articles"
}

module "iam" {
  source = "../../modules/iam"

  name_prefix        = local.name_prefix
  dynamodb_table_arn = module.dynamodb.table_arn
  dynamodb_gsi_arn   = module.dynamodb.gsi1_arn
}

module "ecs" {
  source = "../../modules/ecs"

  name_prefix         = local.name_prefix
  vpc_id              = data.aws_vpc.default.id
  subnet_ids          = data.aws_subnets.default.ids
  image_uri           = local.image_uri
  dynamodb_table_name = module.dynamodb.table_name
  aws_region          = var.region

  task_execution_role_arn = module.iam.task_execution_role_arn
  api_task_role_arn       = module.iam.api_task_role_arn
  fetcher_task_role_arn   = module.iam.fetcher_task_role_arn
}

module "scheduler" {
  source = "../../modules/scheduler"

  name_prefix                 = local.name_prefix
  schedule_expression         = var.fetcher_schedule
  ecs_cluster_arn             = module.ecs.cluster_arn
  fetcher_task_definition_arn = module.ecs.fetcher_task_definition_arn
  task_execution_role_arn     = module.iam.task_execution_role_arn
  fetcher_task_role_arn       = module.iam.fetcher_task_role_arn
  subnet_ids                  = data.aws_subnets.default.ids
  security_group_id           = module.ecs.fetcher_security_group_id
}

module "spa" {
  source                      = "../../modules/s3-spa"
  name                        = "${local.name_prefix}-spa-${data.aws_caller_identity.current.account_id}"
  cloudfront_distribution_arn = module.cloudfront.distribution_arn
}

module "cloudfront" {
  source = "../../modules/cloudfront"

  name_prefix                     = local.name_prefix
  alb_dns_name                    = module.ecs.alb_dns_name
  spa_bucket_regional_domain_name = module.spa.bucket_regional_domain_name
  spa_bucket_id                   = module.spa.bucket_name
}

# ────────── Outputs ──────────

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "dynamodb_table" {
  value = module.dynamodb.table_name
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_api_service" {
  value = module.ecs.api_service_name
}

output "alb_dns_name" {
  value = module.ecs.alb_dns_name
}

output "spa_bucket" {
  value = module.spa.bucket_name
}

output "cloudfront_url" {
  value = "https://${module.cloudfront.distribution_domain_name}"
}

output "cloudfront_distribution_id" {
  value = module.cloudfront.distribution_id
}

output "fetcher_task_definition_family" {
  value = module.ecs.fetcher_task_family
}
