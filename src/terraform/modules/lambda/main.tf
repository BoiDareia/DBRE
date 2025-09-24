module "lambda_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "8.0.1"

  # common configuration for both powershell and python functions, differences are handled in the environment specific main.tf files
  function_name = var.function_name
  handler       = var.handler
  runtime       = var.runtime

  publish = true

  source_path = {
    path = var.source_path
  }
  local_existing_package            = var.local_existing_package
  create_package                    = var.create_package
  layers                            = var.layers

  create_role                       = false
  lambda_role                       = var.lambda_role
  environment_variables             = var.environment_variables
  vpc_security_group_ids            = var.vpc_security_group_ids
  vpc_subnet_ids                    = var.vpc_subnet_ids
  tags                              = var.tags
  timeout                           = var.timeout
  memory_size                       = var.memory_size
  cloudwatch_logs_retention_in_days = var.cloudwatch_logs_retention_in_days
  cloudwatch_logs_tags              = var.cloudwatch_logs_tags
}

