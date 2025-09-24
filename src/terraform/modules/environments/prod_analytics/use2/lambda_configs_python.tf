locals {
  lambda_configs_python = {
    
        DBA-SnapShot-Post-Restore-Validation = {

      handler       = "lambda_function.lambda_handler" 
      runtime       = "python3.13"
      #name = ""  #Optional, will default to the key name when not used


      lambda_role            = "arn:aws:iam::${local.account}:role/PerformanceInsightsCounterMetricsRole"
      environment_variables  = {
        AWS_BUCKET = null
        AWS_SOURCE_REGION = null
      }
      vpc_security_group_ids = null
      vpc_subnet_ids         = null

      tags        = local.default_tags
      timeout     = 120
      layers      = ["arn:aws:lambda:${local.default_region}:${local.account}:layer:dba-db-drivers-python3-13:1"]
      memory_size = local.default_memory_size

    }


  }
}

