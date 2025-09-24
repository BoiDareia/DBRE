module "lambda_function_powershell" {
  for_each = local.lambda_configs_powershell

  source = "../../../lambda/"

  
  function_name = each.key # Name of the function matches the key in the lambda_configs_powershell map

  # Handler for the function, matches the function main file, usually it is the name of the funciton but when the variable name is used it will override it in case we want to use the same code for different functions
  handler       = "${lookup(each.value, "name", each.key)}::${replace(lookup(each.value, "name", each.key), "-", "_")}.Bootstrap::ExecuteFunction" # Handler for the function, using the function name with underscores instead of dashes
  runtime       = each.value.runtime

  source_path   = null #Path to the source code of the function, null for powershell since we need to pre compile the code
  
  # Path to the existing package, created beforehand, example: New-AWSPowerShellLambdaPackage -ScriptPath ../../../lambda/functions/<functionname>/<functionname>.ps1 -OutputPackage ../../../lambda/functions/<functionname>/<functionname>.zip
  # When there is the need to create multiple functions with the same code, the name variable can be used to differentiate them
  local_existing_package = "../../../lambda/functions/${lookup(each.value, "name", each.key)}/${lookup(each.value, "name", each.key)}.zip"  
                                                                                    # Folder structure: lambda/functions/<function_name>/<function_name>.zip
  create_package = false # We are not creating a package, we are using an existing one
  
  #common configuration for all functions, powershell or python
  lambda_role   = each.value.lambda_role
  environment_variables = each.value.environment_variables
  vpc_security_group_ids = each.value.vpc_security_group_ids
  vpc_subnet_ids         = each.value.vpc_subnet_ids

  tags = local.default_tags
  timeout = each.value.timeout
  layers = each.value.layers
  memory_size = each.value.memory_size
  cloudwatch_logs_retention_in_days = local.default_log_group_retention_in_days
  cloudwatch_logs_tags              = local.default_tags
}


module "lambda_function_python" {
  for_each = local.lambda_configs_python

  source = "../../../lambda/"

  function_name = each.key # Name of the function matches the key in the lambda_configs_python map
  handler       = each.value.handler # Handler for the function, matches the function main file
  runtime       = each.value.runtime

  # Path to the source code of the function, if not null, it will be used to create a package
  # When the optional name is provided it will be used to find the code, when not provided it will expect the function name to match the script file name
  # This allows for the versatility of reusing the same code for different functions, like for the case of DBA-CreateDRInstance function
  source_path = "../../../lambda/functions/${lookup(each.value, "name", each.key)}"
                                                          # Folder structure: lambda/functions/<function_name>
  local_existing_package = null # Path to the existing package, null for python since the code will be compiled on the fly
  create_package = true # We are creating a package from the python source code
  
  #common configuration for all functions, powershell or python

  lambda_role   = each.value.lambda_role
  environment_variables = each.value.environment_variables
  vpc_security_group_ids = each.value.vpc_security_group_ids
  vpc_subnet_ids         = each.value.vpc_subnet_ids

  tags        = local.default_tags
  timeout     = each.value.timeout
  layers      = each.value.layers
  memory_size = each.value.memory_size
  cloudwatch_logs_retention_in_days = local.default_log_group_retention_in_days
  cloudwatch_logs_tags              = local.default_tags
}


module "lambda_layer" {
  for_each = local.lambda_configs_layers

  source = "../../../layers/"

  layer_name = each.key # Name of the layer matches the key in the lambda_configs_layers map
  runtimes =    each.value.runtimes
  compatible_architectures = each.value.compatible_architectures

  local_existing_package = "../../../layers/packages/${each.key}/${each.key}.zip" # Path to the existing package with the layer code
 
}