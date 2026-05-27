terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70"
    }
  }
}

variable "name_prefix" { type = string }
variable "schedule_expression" { type = string }
variable "ecs_cluster_arn" { type = string }
variable "fetcher_task_definition_arn" { type = string }
variable "task_execution_role_arn" { type = string }
variable "fetcher_task_role_arn" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }

resource "aws_iam_role" "scheduler" {
  name = "${var.name_prefix}-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Scheduler needs to ecs:RunTask on the family (any revision) and PassRole the
# task roles into ECS.
resource "aws_iam_role_policy" "scheduler" {
  name = "run-task"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "ecs:RunTask"
        Resource = [
          "${replace(var.fetcher_task_definition_arn, "/:[0-9]+$/", "")}:*",
          replace(var.fetcher_task_definition_arn, "/:[0-9]+$/", ""),
        ]
        Condition = {
          ArnLike = {
            "ecs:cluster" = var.ecs_cluster_arn
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [var.task_execution_role_arn, var.fetcher_task_role_arn]
      },
    ]
  })
}

resource "aws_scheduler_schedule" "fetcher" {
  name       = "${var.name_prefix}-fetcher"
  group_name = "default"

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = var.ecs_cluster_arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = replace(var.fetcher_task_definition_arn, "/:[0-9]+$/", "")
      launch_type         = "FARGATE"
      task_count          = 1

      network_configuration {
        subnets          = var.subnet_ids
        security_groups  = [var.security_group_id]
        assign_public_ip = true
      }
    }

    retry_policy {
      maximum_event_age_in_seconds = 600
      maximum_retry_attempts       = 1
    }
  }
}

output "schedule_name" {
  value = aws_scheduler_schedule.fetcher.name
}

output "scheduler_role_arn" {
  value = aws_iam_role.scheduler.arn
}
