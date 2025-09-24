locals {
  #different defaults for different regions
  account     = "SET-ACCOUNT-NUMBER"
  vpc_sg_main = ["sg-044dbxxxxxyyyzzzz"] # different per account
  vpc_subnets_main = [
        "subnet-095af9xxxxxyyzzzz",
        "subnet-0af7b7xxxxxyyzzzz",
        "subnet-05b417xxxxxyyzzzz",
        "subnet-0d9aba1xxxxxyyzzzz",
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