variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "source_path" {
  description = "Path to the source code"
  type        = string
}

variable "runtime" {
  description = "Runtime for the Lambda function"
  type        = string
}

variable "handler" {
  description = "Handler for the Lambda function"
  type        = string
}

variable "environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
}

variable "tags" {
  description = "Tags to be applied to the Lambda function"
  type        = map(string)
}

variable "lambda_role" {
  description = "ARN of the IAM role to attach to the Lambda function"
  type        = any
}

variable "vpc_security_group_ids" {
  description = "List of VPC security group IDs"
  type        = list(string)
}

variable "vpc_subnet_ids" {
  description = "List of VPC subnet IDs"
  type        = list(string)
}

variable "timeout" {
  description = "Timeout for the function"
  type        = number
  default     = 900
}

variable "local_existing_package" {
  description = "The absolute path to an existing zip-file, created by New-AWSPowerShellLambdaPackage"
  type        = string
}

variable "create_package" {
  description = "Controls whether Lambda Layer resource should be created"
  type        = bool
}

variable "layers" {
  description = "List of Lambda Layer Version ARNs (maximum of 5) to attach to your Lambda Function."
  type        = list(string)
}

variable "memory_size" {
  description = "Amount of memory in MB your Lambda Function can use at runtime. Valid value between 128 MB to 3008 MB, in 64 MB increments."
  type        = number
}

variable "cloudwatch_logs_retention_in_days" {
  description = "The number of days log events are kept in CloudWatch Logs."
  type        = number
  default     = 30
}

variable "cloudwatch_logs_tags" {
  description = "Tags to be applied to CloudWatch Logs"
  type        = map(string)
}