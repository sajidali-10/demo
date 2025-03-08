provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
}

resource "aws_eip" "nat" {}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_s3_bucket" "storage" {
  bucket = "my-app-storage"
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "my-api"
  description = "API Gateway for my application"
}

resource "aws_security_group" "lambda_sg" {
  vpc_id = aws_vpc.main.id
}

resource "aws_lambda_function" "lambda_functions" {
  for_each     = toset([
    "HipText-v3-qa-getmappednumbers",
    "HipText-v3-qa-outageautodetection",
    "HipText-v3-qa-query",
    "HipText-v3-qa-message",
    "HipText-v3-qa-smschat",
    "HipText-v3-qa-aggregatereportgenerator",
    "HipText-v3-qa-bandwidthstatuscallback",
    "HipText-v3-qa-nexmostatuscallback",
    "HipText-v3-qa-archivereports",
    "HipText-v3-qa-upload",
    "HipText-v3-qa-messagecleanup",
    "HipText-v3-qa-smschatquery"
  ])
  function_name = each.value
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_exec.arn
  filename      = "lambda.zip"
  vpc_config {
    subnet_ids         = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier     = "aurora-cluster"
  engine                = "aurora-mysql"
  engine_mode           = "provisioned"
  database_name         = "productiondb"
  master_username       = "admin"
  master_password       = "password"
  db_subnet_group_name  = aws_db_subnet_group.aurora_subnet_group.name
  serverlessv2_scaling_configuration {
    min_capacity = 1
    max_capacity = 4
  }
}

resource "aws_db_subnet_group" "aurora_subnet_group" {
  name       = "aurora_subnet_group"
  subnet_ids = [aws_subnet.private.id]
}

resource "aws_instance" "ec2" {
  ami                         = "ami-0c55b159cbfafe1f0"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
}

resource "aws_cloudwatch_log_group" "logs" {
  name = "/aws/lambda/logs"
}

resource "aws_sns_topic" "alerts" {
  name = "alerts"
}

resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "admin@example.com"
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}
