locals {
  lambda_configs_powershell = {
    
     DBA-TableRecordCount = {


      runtime       = "dotnet8"
      lambda_role   = "arn:aws:iam::${local.account}:role/CallRDSStoredProcedures"
      #name = ""  #Optional, will default to the key name when not used


      environment_variables = {
        CLOUDWATCH_CUSTOM_NAMESPACE = "DBRecordCounts"
        METRIC_VALUE                = "RecordsCreated"
        RDS_INSTANCE                = "rdseuw.company-dev.com"
        RDS_SECRET_ID               = "set-secret"
        SOURCE_REGION               = "eu-west-1"
        SP_NAME                     = "[dbo].[table_record_metrics]"
      }

      vpc_security_group_ids = local.vpc_sg_main
      vpc_subnet_ids         = local.vpc_subnets_main

      timeout     = local.default_timeout
      layers      = local.default_layers
      memory_size = local.default_memory_size
    }


  }
}

