module "lambda_layer" {
  source = "terraform-aws-modules/lambda/aws"
  version = "8.0.1"

  # main layer configuration
  create_layer = true # We are creating a layer
  create_package = false # We are not creating a package, we are using an existing one

  layer_name          = var.layer_name
  compatible_runtimes = var.runtimes
  compatible_architectures = var.compatible_architectures

  local_existing_package = var.local_existing_package
}


