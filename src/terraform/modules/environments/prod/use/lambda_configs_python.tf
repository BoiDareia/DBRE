locals {
  lambda_configs_python = {
    
    /*
    DBA-pom-migration-export-s3 = {

      handler       = "lambda_function.lambda_handler"
      runtime       = "python3.11"
      #name = ""  #Optional, will default to the key name when not used


      lambda_role            = "arn:aws:iam::${local.account}:role/CallRDSStoredProcedures"
      environment_variables = {
        AWS_BUCKET = "rds-bkup-use"
        AWS_INSTANCE = "rdsuse.company.com"
        AWS_SECRET = "set-secret"
      }
      vpc_security_group_ids = local.vpc_sg_main
      vpc_subnet_ids         = local.vpc_subnets_main

      timeout     = local.default_timeout
      layers      = ["arn:aws:lambda:${local.default_region}:${local.account}:layer:dba-pyodbc:1"]
      memory_size = 10240

    }
    */


  }
}

