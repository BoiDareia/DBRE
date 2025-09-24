variable "layer_name" {
  description = "Layer name"
  type        = string
}

variable "local_existing_package" {
  description = "The absolute path to an existing zip-file, created by New-AWSPowerShellLambdaPackage"
  type        = string
}

variable "runtimes" {
  description = "List of runtimes"
  type        = list(string)
}

variable "compatible_architectures" {
  description = "List of compatible architectures"
  type        = list(string)
}




