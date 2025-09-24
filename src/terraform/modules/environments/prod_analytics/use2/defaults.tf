locals {
  #different defaults for different regions
  account     = "SET-ACCOUNT-NUMBER"
  vpc_sg_main = []
  vpc_subnets_main = [
      ]
  default_region = "us-east-2"

  #common default values
  default_timeout = 900
  default_memory_size = 256
  default_layers = null

  #default values that are not expected to change per function
  default_tags = {team = "dba"}
  default_log_group_retention_in_days = 30

}