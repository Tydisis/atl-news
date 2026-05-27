terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70"
    }
  }
}

variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "image_uri" { type = string }
variable "dynamodb_table_name" { type = string }
variable "aws_region" { type = string }

variable "task_execution_role_arn" { type = string }
variable "api_task_role_arn" { type = string }
variable "fetcher_task_role_arn" { type = string }

variable "api_cpu" {
  type    = number
  default = 256
}
variable "api_memory" {
  type    = number
  default = 512
}
variable "api_desired_count" {
  type    = number
  default = 1
}

variable "fetcher_cpu" {
  type    = number
  default = 512
}
variable "fetcher_memory" {
  type    = number
  default = 1024
}

# ────────── Cluster + logs ──────────

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.name_prefix}/api"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "fetcher" {
  name              = "/ecs/${var.name_prefix}/fetcher"
  retention_in_days = 14
}

# ────────── Security groups ──────────

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "Public ingress to the ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "api_task" {
  name        = "${var.name_prefix}-api-task"
  description = "API tasks; ingress only from ALB SG"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound (DynamoDB, ECR, CloudWatch)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "fetcher_task" {
  name        = "${var.name_prefix}-fetcher-task"
  description = "Fetcher tasks; outbound only"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound (RSS, DynamoDB, ECR, CloudWatch)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ────────── ALB ──────────

resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
}

resource "aws_lb_target_group" "api" {
  name        = "${var.name_prefix}-api-tg"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    path                = "/healthz"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 15
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# ────────── Task definitions ──────────

locals {
  common_env = [
    { name = "ATL_STORE_BACKEND", value = "dynamodb" },
    { name = "ATL_DYNAMODB_TABLE", value = var.dynamodb_table_name },
    { name = "ATL_AWS_REGION", value = var.aws_region },
  ]
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name_prefix}-api"
  cpu                      = var.api_cpu
  memory                   = var.api_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.api_task_role_arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name        = "api"
      image       = var.image_uri
      essential   = true
      command     = ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
      portMappings = [{ containerPort = 8000, protocol = "tcp" }]
      environment = local.common_env
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "api"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status==200 else 1)\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }
    }
  ])
}

resource "aws_ecs_task_definition" "fetcher" {
  family                   = "${var.name_prefix}-fetcher"
  cpu                      = var.fetcher_cpu
  memory                   = var.fetcher_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.fetcher_task_role_arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name        = "fetcher"
      image       = var.image_uri
      essential   = true
      command     = ["python", "-m", "app.fetcher_cli"]
      environment = local.common_env
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.fetcher.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "fetcher"
        }
      }
    }
  ])
}

# ────────── API service ──────────

resource "aws_ecs_service" "api" {
  name            = "${var.name_prefix}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.api_task.id]
    assign_public_ip = true # default VPC public subnets, no NAT
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api"
    container_port   = 8000
  }

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [task_definition] # deploys can update without TF
  }
}

output "cluster_arn" { value = aws_ecs_cluster.this.arn }
output "cluster_name" { value = aws_ecs_cluster.this.name }
output "alb_dns_name" { value = aws_lb.this.dns_name }
output "alb_arn" { value = aws_lb.this.arn }
output "fetcher_task_definition_arn" { value = aws_ecs_task_definition.fetcher.arn }
output "fetcher_task_family" { value = aws_ecs_task_definition.fetcher.family }
output "fetcher_security_group_id" { value = aws_security_group.fetcher_task.id }
output "api_service_name" { value = aws_ecs_service.api.name }
