locals {
  #different defaults for different regions
  account     = SET-ACCOUNT-NUMBER
  vpc_sg_main = ["sg-0aaacxxxxx"]
  vpc_subnets_main = [
        "subnet-0258d2xxxxxx",
        "subnet-07656xxxxxxx",
        "subnet-0c580dxxxxxxx",
        "subnet-03aa82axxxxxx",
        "subnet-05ef374xxxxxx"
      ]
  default_region = "us-east-1"

  #common default values
  default_timeout = 900
  default_memory_size = 256
  default_layers = null

  #default values that are not expected to change per function
  default_tags = {team = "dba"}
  default_log_group_retention_in_days = 30
  
}