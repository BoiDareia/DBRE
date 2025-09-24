locals {
  #different defaults for different regions
  account     = SET-ACCOUNT-NUMBER
  vpc_sg_main = ["sg-0e8xxxxxxbxxxxxx"] # different per account
  vpc_subnets_main = [
        "subnet-0908cxxxxxxxe3xxxx",
        "subnet-057fxxxxxx4xxxxxx",
        "subnet-0aec0xxxxxx7xxxxxx",
        "subnet-0029dxxxxxx8xxxxxx",
      ]
  default_region = "eu-central-1"

  #common default values
  default_timeout = 900
  default_memory_size = 256
  default_layers = null

  #default values that are not expected to change per function
  default_tags = {team = "dba"}
  default_log_group_retention_in_days = 30
  
}