terraform {
  backend "s3" {
    bucket  = "tf-company-backend" # different per account
    key     = "env/company-analytics-prod/us-east-2/dba/dba.tfstate" # different per region and account
    region  = "eu-west-1" # always eu-west-1, devops only configured one bucket per account to store tfstate files
    encrypt = true
    acl     = "bucket-owner-full-control"
  }
}