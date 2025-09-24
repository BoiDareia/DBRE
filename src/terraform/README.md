## Repo
====

This is a folder n the main repo to include the functions managed with Terraform.

### .gitignore
----------

The execution of terraform commands generates a lot of files in specific directories, mainly **.terraform** and **builds**

In **.terraform** we have the downloaded aws provider (over 500MB) and our modules created with terraform initialization

In **builds** we have the packages for any Python function since these are built during the deploy

We don't need these to be versioned into our repo so we ignore them and version only the relevant information: actual code, prepackaged Powershell functions and environment info

```
# Local .terraform directories
**/.terraform/*
**/builds/*

# .tfstate files
*.tfstate
*.tfstate.*
```

We allow the versioning of **zip** files, that way we always store the last compiled package for a Powershell function

## Structure
=========

This is the general structure for the solution.

The active work will be done in the files in the **environments** folders, and copy of source code/packages to the respective **functions** and **packages** folders

![image-20240905-094658.png](/docs/images/tf/image-20240905-094658.png)

### Lambda
------

![image-20240829-090512.png](/docs/images/tf/image-20240829-090512.png)

The terraform files listed should not need any changes now that the process is working, these are the files that manage the configuration of any Lambda function.

Inside the **functions** directory, we will copy the functions code we already have in the repo root

![image-20240905-094751.png](/docs/images/tf/image-20240905-094751.png)

### Layers
------

![image-20240829-110314.png](/docs/images/tf/image-20240829-110314.png)

For some functions, we might have the need to create a custom layer. This template supports the storage of zip files with the packaged code

### Environments
------------

![image-20240829-090646.png](/docs/images/tf/image-20240829-090646.png)

We follow a structure of **environment/region** and each pair has its own location for the terraform state file

It is in these folders that we keep the Lambda configurations (that might be different per environment/region)

### Defaults file

In this file, we store all the default parameters that can be used by any function.

The top ones will always be different.

The bottom ones should be defaults **across our platform** and if we need to change any of these, they should be changed in the defaults file for **all environments**

**A separation is made between common default values and tags/log group retention** because the common ones can be overridden in the specific function configuration, while the other 2 parameters we expect that if they ever change, they are supposed to be changed to all available functions

<details>

**<summary>Code</summary>**

```
locals {
  #different defaults for different regions
  account     = 983256399917
  vpc_sg_main = ["sg-0aaaceb325fffa6d1"]
  vpc_subnets_main = [
        "subnet-0258d270bb74efd8a",
        "subnet-07656ac3803cda6e9",
        "subnet-0c580de40a53239b0",
        "subnet-03aa82acd274c6565",
        "subnet-05ef374c24077e5ed"
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
```
</details>

### Backend file

The backend file is where we state where we store our **tfstate** file, that will record all the objects deployed:

<details>

**<summary>Code</summary>**
```
terraform {
  backend "s3" {
    bucket  = "tf-company-backend-9917"
    key     = "env/company-apps-dev/us-east-1/dba/dba.tfstate"
    region  = "eu-west-1"
    encrypt = true
    acl     = "bucket-owner-full-control"
  }
}
```
</details>

region is **always eu-west-1** because it seems the devops tf bucket is always in the EU region

### Versions file


This file contains the provider for the environment/region, the **provider** entry needs to match the **aws region**:

```
provider "aws" {
  region = "us-east-1" # Must be modified to match the intended region
}
```

## Local setup
==============

Visual Studio Code is good to work with Terraform, and the following extensions should be installed:

![image-20240829-103623.png](/docs/images/tf/image-20240829-103623.png)

To connect to the environments, you need saml2aws configured in Visual Studio Code.

### Powershell
----------

Specific to be able to package Powershell functions, we need to (use "Run as Administrator"):

1.  Install Powershell 7 [Installing PowerShell on Windows - PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4)
   
    `winget install --id Microsoft.PowerShell --source winget`

2.  Make sure the session in Visual Studio Code is using this powershell for the session, it needs to be the one named **pwsh** (not "powershell")

    ![image-20240905-100619.png](/docs/images/tf/image-20240905-100619.png)

3.  Install-Module AWSLambdaPSCore

## How to deploy
=================

1.  Login to the account you are deploying to:\
    **`saml2aws login -a company-apps-dev`**

2.  Set the environment variable AWS_PROFILE to the account you just logged in:\
    **`$env:AWS_PROFILE="company-apps-dev"`**

3.  Change to the environment/region you want to deploy:\
    **`cd .\tf-modules\environments\dev\use`**

4.  Initialize the terraform environment/region with the specific provider\
    **`terraform init`**

5.  Validate the changes to be applied:\
    **`terraform plan`**

6.  Apply the changes (runs an implicit **plan** before asking for confirmation before applying):\
    **`terraform apply`**

<details>

**<summary>Example of update to the DBA-pom-migration-export-s3 function</summary>**

```
Terraform used the selected providers to generate the following execution plan. Resource actions are indicated with the following symbols:
  ~ update in-place
+/- create replacement and then destroy

Terraform will perform the following actions:

  # module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.aws_lambda_function.this[0] will be updated in-place
  ~ resource "aws_lambda_function" "this" {
      ~ filename                       = "builds\\4f2ced734f28a27de53cde912420ae91c0d459c286c563f7c3a75269232ffb6c.zip" -> "builds\\a2bfac09788a207f516ab2d2148b9a80836f0a8760a8f0e47e95e8954ac8848f.zip"
        id                             = "DBA-pom-migration-export-s3"
      ~ last_modified                  = "2024-08-07T14:14:17.000+0000" -> (known after apply)
      ~ qualified_arn                  = "arn:aws:lambda:us-east-1:055566514766:function:DBA-pom-migration-export-s3:2" -> (known after apply)
      ~ qualified_invoke_arn           = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:055566514766:function:DBA-pom-migration-export-s3:2/invocations" -> (known after apply)
        tags                           = {
            "team"                  = "dba"
            "terraform-aws-modules" = "lambda"
        }
      ~ version                        = "2" -> (known after apply)
        # (24 unchanged attributes hidden)

        # (5 unchanged blocks hidden)
    }

  # module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.local_file.archive_plan[0] must be replaced
+/- resource "local_file" "archive_plan" {
      ~ content              = jsonencode(
          ~ {
              ~ filename      = "builds\\4f2ced734f28a27de53cde912420ae91c0d459c286c563f7c3a75269232ffb6c.zip" -> "builds\\a2bfac09788a207f516ab2d2148b9a80836f0a8760a8f0e47e95e8954ac8848f.zip"
                # (3 unchanged attributes hidden)
            } # forces replacement
        )
      ~ content_base64sha256 = "4+2wd671dH3ITiiC3wnuieb//5ujNTrgLJr7wP8+jQI=" -> (known after apply)
      ~ content_base64sha512 = "NJOq6gwsPx0V6J0wwGMJqBgduSqMeI9bPKN3cD+4tJAj4XRTjlKTgKR7JT93KLc1YXd5TmN2J3oP4DGFhZ7UrA==" -> (known after apply)
      ~ content_md5          = "a3f9fe49e84fa1f0acad4c131adb4c1f" -> (known after apply)
      ~ content_sha1         = "548642d227c4d04e8dbf4d6bb82f22cc15c67857" -> (known after apply)
      ~ content_sha256       = "e3edb077aef5747dc84e2882df09ee89e6ffff9ba3353ae02c9afbc0ff3e8d02" -> (known after apply)
      ~ content_sha512       = "3493aaea0c2c3f1d15e89d30c06309a8181db92a8c788f5b3ca377703fb8b49023e174538e529380a47b253f7728b7356177794e6376277a0fe03185859ed4ac" -> (known after apply)
      ~ filename             = "builds\\4f2ced734f28a27de53cde912420ae91c0d459c286c563f7c3a75269232ffb6c.plan.json" -> "builds\\a2bfac09788a207f516ab2d2148b9a80836f0a8760a8f0e47e95e8954ac8848f.plan.json" # forces replacement
      ~ id                   = "548642d227c4d04e8dbf4d6bb82f22cc15c67857" -> (known after apply)
        # (2 unchanged attributes hidden)
    }

  # module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.null_resource.archive[0] must be replaced
+/- resource "null_resource" "archive" {
      ~ id       = "1734990918" -> (known after apply)
      ~ triggers = { # forces replacement
          ~ "filename"  = "builds\\4f2ced734f28a27de53cde912420ae91c0d459c286c563f7c3a75269232ffb6c.zip" -> "builds\\a2bfac09788a207f516ab2d2148b9a80836f0a8760a8f0e47e95e8954ac8848f.zip"
          ~ "timestamp" = "1722272207954418800" -> "1723223121655325000"
        }
    }

Plan: 2 to add, 1 to change, 2 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.local_file.archive_plan[0]: Creating...
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.local_file.archive_plan[0]: Creation complete after 0s [id=02852baa1dcde8df720d8f2d24479ef1016d2cd7]
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.null_resource.archive[0]: Creating...
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.null_resource.archive[0]: Provisioning with 'local-exec'...
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.null_resource.archive[0] (local-exec): Executing: ["python.exe" ".terraform/modules/lambda_function_python.lambda_function/package.py" "build" "--timestamp" "1723223121655325000" "builds\\a2bfac09788a207f516ab2d2148b9a80836f0a8760a8f0e47e95e8954ac8848f.plan.json"]
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.null_resource.archive[0] (local-exec): zip: creating 'builds\a2bfac09788a207f516ab2d2148b9a80836f0a8760a8f0e47e95e8954ac8848f.zip' archive
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.null_resource.archive[0] (local-exec): zip: adding content of directory: ../../../lambda/functions/DBA-pom-migration-export-s3
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.null_resource.archive[0] (local-exec): zip: adding: lambda_function.py
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.null_resource.archive[0] (local-exec): Created: 'builds\a2bfac09788a207f516ab2d2148b9a80836f0a8760a8f0e47e95e8954ac8848f.zip'
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.null_resource.archive[0]: Creation complete after 0s [id=97601026]
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.aws_lambda_function.this[0]: Modifying... [id=DBA-pom-migration-export-s3]
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.aws_lambda_function.this[0]: Modifications complete after 9s [id=DBA-pom-migration-export-s3]
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.null_resource.archive[0] (deposed object 9b661ab9): Destroying... [id=1734990918]
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.null_resource.archive[0]: Destruction complete after 0s
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.local_file.archive_plan[0] (deposed object 6996cd49): Destroying... [id=548642d227c4d04e8dbf4d6bb82f22cc15c67857]
module.lambda_function_python["DBA-pom-migration-export-s3"].module.lambda_function.local_file.archive_plan[0]: Destruction complete after 0s

Apply complete! Resources: 2 added, 1 changed, 2 destroyed.
```
</details>

## Add/Remove functions/layers to an environment
================================================

### Python function
-------------------

![image-20240905-094910.png](/docs/images/tf/image-20240905-094910.png)

**By default, the function entry name will match the function directory/name.**

If there is the need to have multiple copies of a Lambda function that point to the same code, this can be achieved with the optional **name** variable, as in the example below.

Additionally, the lambda handler needs be the **exactly the same** as the main python file name in the function

`function_name = each.key # Name of the function matches the key in the lambda_configs_python map`\
`handler = "app.lambda_handler" # Handler for the function, matches the function main file, app.py`

<details>

<summary>Python function configuration example</summary>

```
DBA-CreateDRInstance-Nicelabel = {

      handler       = "lambda_function.lambda_handler" # Format: <main filename>.lambda_handler
      runtime       = "python3.12" # Python runtime version
      name = "DBA-CreateDRInstance"  #Optional, will default to the key name when not used


      lambda_role            = "arn:aws:iam::${local.account}:role/DBA-DRSnapshot" # ARN of the role to be used by the lambda function, local.account will allow for this line to be copied accross environments

      # Environment variables for the lambda function, if needed
      environment_variables = {
        AWS_INSTANCE_IDENTIFIER = "prod-nicelabel"
        AWS_OPTION_GROUP = "option-group-nicelable-se-2022"
        AWS_PARAM_GROUP = "prod-nicelabel-custom-parameter-group-se-2022"
        AWS_PREFERRED_ZONE = "eu-west-1b"
        AWS_SECURITY_GROUP = "sg-0ad7exxxgbxgx"
        AWS_STORAGE_THROUGHPUT = 125
        AWS_SUBNET_GROUP = "rds-subnet"
        AWS_PARAM_GROUP = "rds-pg-produps-eu-west-1-custom"
      }

      # Security group and subnets for the lambda function, most of the time will be the same for all functions
      vpc_security_group_ids = null
      vpc_subnet_ids         = null


      tags        = local.default_tags # Tags for the lambda function, team:dba for now
      timeout     = local.default_timeout # Timeout for the lambda function, default is the max of 15 minutes, override if needed
      layers      = local.default_layers # Layers for the lambda function, null for now
      memory_size = local.default_memory_size # Memory size for the lambda function, default is 256, override if needed (in this case we need 10240)

    }
```
</details>

### Powershell function
-----------------------

![image-20240905-094939.png](/docs/images/tf/image-20240905-094939.png)

**By default, the function entry name will match the function directory/name.**

**The same is true for the package name**

If there is the need to have multiple copies of a Lambda function that point to the same code, this can be achieved with the optional **name** variable, as in the example below.

`function_name = each.key # Name of the function matches the key in the lambda_configs_powershell map`\
...\
`local_existing_package = "../../../lambda/functions/${lookup(each.value, "name", each.key)}/${lookup(each.value, "name", each.key)}.zip"`


<details>

<summary>Powershell function configuration example</summary>

```
DBA-TableRecordCount = {

      runtime       = "dotnet8"
      lambda_role   = "arn:aws:iam::${local.account}:role/DBA-CallRDSStoredProcedures"
      #name = ""  #Optional, will default to the key name when not used

      environment_variables = {
        CLOUDWATCH_CUSTOM_NAMESPACE = "DBRecordCounts"
        METRIC_VALUE                = "RecordsCreated"
        RDS_INSTANCE                = "rdsuse.company-dev2.com"
        RDS_SECRET_ID               = "set-secret"
        SOURCE_REGION               = "us-east-1"
        SP_NAME                     = "[dbo].[table_record_metrics]"
      }

      vpc_security_group_ids = local.vpc_sg_main
      vpc_subnet_ids         = local.vpc_subnets_main

      timeout     = local.default_timeout
      layers      = local.default_layers
      memory_size = local.default_memory_size
    }
```
</details>

To create a package for your Powershell code, and store it in the specific function folder, you need to execute the following commands:

`Import-Module AWSLambdaPSCore`

`New-AWSPowerShellLambdaPackage -ScriptPath ../../../lambda/functions/<functionname>/<functionname>.ps1 -OutputPackage ../../../lambda/functions/<functionname>/<functionname>.zip`

**Every time the code for a powershell function is modified, it needs to be repackaged for deploy (or you will be just deploying the old code)**

**If there is no package to upload, you will get an error like this:**

**Error: reading ZIP file** (../../../lambda/functions/DBA-TableRecordCount/DBA-TableRecordCount.zip):open ../../../lambda/functions/DBA-TableRecordCount/DBA-TableRecordCount.zip: **The system cannot find the file specified.**

### Layer
---------

![image-20240830-135646.png](/docs/images/tf/image-20240830-135646.png)

To create a custom layer, similar to Powershell, the lambda entry needs to be **exactly the same** as the directory name in the layers directory and the **same is true for the package name**

`layer_name = each.key # Name of the layer matches the key in the lambda_configs_layers map`\
...

`local_existing_package = "../../../layers/packages/${each.key}/${each.key}.zip" # Path to the existing package with the layer code`

<details>

<summary>Layer configuration example</summary>

```
lambda_configs_layers = {
    
    dba-pyodbc = {

      runtimes       = ["python3.11"]
      compatible_architectures = ["x86_64"]
    }
  }
```
</details>

### Add Functions
-----------------

New functions should always start as a copy of the entry above in the relevant **lambda_configs** file, and then edit any parameter you need.

For any parameter that uses **local.** variables, these come from the defaults file since most of the time we will use the same configurations. You can override any parameter and use what you need instead of the **local.** if you need

### Remove functions
--------------------

To remove a function, simply remove the entry from the **lambda_configs** file.

This way we keep the code in the functions directory as archive, and we can always reconfigure and redeploy in the future.

**terraform apply** following the entry removal will remove the function from the environment

***There should **never** be a case when we use **terraform destroy*****
***It will remove all functions for that environment that are present in the tfstate file***

## Create a new environment
==========================

To create a new environment, you start by copying the folder structure from another environment.

Following that, you need to:

-   remove the **.terraform** and **builds** folders

-   edit the **defaults**, **backend**, and **versions** files, to update any parameter that is specific to the new environment

-   remove any entries from the **lambda_configs_python**, **lambda_configs_powershell** and **lambda_layers** from the functions you **DON'T** want to include in the new environment

1.  In the **defaults** file, edit the `account`, `vpc_sg_main`, `vpc_subnets_main and default_region`
    
<details>

<summary>For the security group and subnets, check what is used from existing functions or DB instance</summary>

```
#different defaults for different regions
  account     = SET-ACCOUNT-NUMBER
  vpc_sg_main = ["sg-0aaacexxxfbf"]
  vpc_subnets_main = [
        "subnet-0258d2xxfbd",
        "subnet-07656axxxbngf",
        "subnet-0c580dxxxvbdfb",
        "subnet-03aa82axxcvsdf",
        "subnet-05ef374csddfsdfsd"
      ]
  default_region = "us-east-1"
```
</details>

2.  In the **backend** file, edit the `bucket`and `key`

<details>

<summary>Check which is the tf bucket for that account and change accordingly, try to keep the same structure we use for other environments (you will need to create the dba folder)</summary>

```
terraform {
  backend "s3" {
    bucket  = "tf-company-backend" # different per account
    key     = "env/compnay-apps-dev/us-east-1/dba/dba.tfstate" # different per region and account
    region  = "eu-west-1" # always eu-west-1, devops only configured one bucket per account to store tfstate files
    encrypt = true
    acl     = "bucket-owner-full-control"
  }
}
```
</details>

3.  In the **versions** file, edit `region` to match the aws region

<details>

<summary>Code</summary>

```
provider "aws" {
  region = "us-east-1" # Must be modified to match the intended region
}
```
</details>