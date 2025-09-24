output "lambda_arn" {
  description = "The ARN of the Lambda layer"
  value       = module.lambda_layer.lambda_layer_arn
}