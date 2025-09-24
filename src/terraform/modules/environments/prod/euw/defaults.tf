locals {
  #different defaults for different regions
  account     = "SET-ACCOUNT-NUMBER"
  vpc_sg_main = ["sg-dea976b8"]
  vpc_subnets_main = [
        "subnet-604xxxxxx",
        "subnet-03b6f8xxxxxx",
        "subnet-0f8b786xxxxxx"
      ]
  default_region = "eu-west-1"

  #common default values
  default_timeout = 900
  default_memory_size = 256
  default_layers = null

  #default values that are not expected to change per function
  default_tags = {team = "dba"}
  default_log_group_retention_in_days = 30
  
}