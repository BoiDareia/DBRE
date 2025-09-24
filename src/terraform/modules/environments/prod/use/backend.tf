terraform {
  backend "s3" {
    bucket  = "tf-company-backend" # different per account
    key     = "env/company-apps-prod/us-east-1/dba/dba.tfstate" # different per region and account
    region  = "us-east-1" # always us-east-1, devops only configured one bucket per account to store tfstate files
    encrypt = true
    acl     = "bucket-owner-full-control"
  }
}