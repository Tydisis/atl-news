terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70"
    }
  }
}

variable "name_prefix" {
  type = string
}

variable "dynamodb_table_arn" {
  type = string
}

variable "dynamodb_gsi_arn" {
  type = string
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ECS task execution role: shared by both task definitions. Pulls images from ECR
# and ships container logs to CloudWatch.
resource "aws_iam_role" "task_execution" {
  name               = "${var.name_prefix}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# API task role: read-only DynamoDB.
resource "aws_iam_role" "api_task" {
  name               = "${var.name_prefix}-api-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

data "aws_iam_policy_document" "api_dynamodb_read" {
  statement {
    sid    = "ReadArticles"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:BatchGetItem",
    ]
    resources = [
      var.dynamodb_table_arn,
      var.dynamodb_gsi_arn,
    ]
  }
}

resource "aws_iam_role_policy" "api_task" {
  name   = "dynamodb-read"
  role   = aws_iam_role.api_task.id
  policy = data.aws_iam_policy_document.api_dynamodb_read.json
}

# Fetcher task role: read + write DynamoDB.
resource "aws_iam_role" "fetcher_task" {
  name               = "${var.name_prefix}-fetcher-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

data "aws_iam_policy_document" "fetcher_dynamodb_rw" {
  statement {
    sid    = "ReadWriteArticles"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:PutItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:UpdateItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      var.dynamodb_table_arn,
      var.dynamodb_gsi_arn,
    ]
  }
}

resource "aws_iam_role_policy" "fetcher_task" {
  name   = "dynamodb-rw"
  role   = aws_iam_role.fetcher_task.id
  policy = data.aws_iam_policy_document.fetcher_dynamodb_rw.json
}

output "task_execution_role_arn" {
  value = aws_iam_role.task_execution.arn
}

output "api_task_role_arn" {
  value = aws_iam_role.api_task.arn
}

output "fetcher_task_role_arn" {
  value = aws_iam_role.fetcher_task.arn
}
