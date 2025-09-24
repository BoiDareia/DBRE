locals {
  lambda_configs_python = {
    
    /* commented for now, we don't need the function any more but it is a good example
    
    DBA-pom-migration-export-s3 = {

      handler       = "lambda_function.lambda_handler" # Format: <main filename>.lambda_handler
      runtime       = "python3.11" # Python runtime version, override if needed (in this case we need 3.11 instead of 3.12)
      #name = ""  #Optional, will default to the key name when not used


      lambda_role            = "arn:aws:iam::${local.account}:role/CallRDSStoredProcedures" # ARN of the role to be used by the lambda function, local.account will allow for this line to be copied accross environments

      # Environment variables for the lambda function, if needed
      environment_variables = {
        AWS_BUCKET = "rds-restore-euw"
        AWS_INSTANCE = "rdseuw.company-dev.com"
        AWS_SECRET = "set-secret"
      }

      # Security group and subnets for the lambda function, most of the time will be the same for all functions
      vpc_security_group_ids = local.vpc_sg_main
      vpc_subnet_ids         = local.vpc_subnets_main

      timeout     = local.default_timeout # Timeout for the lambda function, default is the max of 15 minutes, override if needed

      layers      = ["arn:aws:lambda:${local.default_region}:${local.account}:layer:dba-pyodbc:2"] # Layers to be used by the lambda function, if needed; version number (the last digit) should be updated to the latest version and might be different between environments
      memory_size = 10240 # Memory size for the lambda function, default is 256, override if needed (in this case we need 10240)

    },*/
    DBA-Cortex-Scorecards = {

      handler       = "app.lambda_handler" 
      runtime       = "python3.12"
      #name = ""  #Optional, will default to the key name when not used


      lambda_role            = "arn:aws:iam::${local.account}:role/PerformanceInsightsCounterMetricsRole"
      environment_variables  = {}
      vpc_security_group_ids = null
      vpc_subnet_ids         = null

      timeout     = local.default_timeout
      layers      = ["arn:aws:lambda:eu-west-1:770693421928:layer:Klayers-p312-requests:8"]
      memory_size = local.default_memory_size

    }
    



  }
}

