locals {
  #different defaults for different regions
  account     = SET-ACCOUNT-NUMBER
  vpc_sg_main = ["sg-00834xxxxbxxxxxx"]
  vpc_subnets_main = [
        "subnet-0e044dxxxbxxxxxx",
        "subnet-0038cxxxxbxxxxxx",
        "subnet-09a63xxxxbxxxxxx",
        "subnet-0c14exxxbxxxxxx",
        "subnet-07b6xxxxxbxxxxxx",
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