locals {
  lambda_configs_layers = {
    
    dba-pyodbc = {

      runtimes       = ["python3.11"]
      compatible_architectures = ["x86_64"]
    },
    dba-db-drivers-python3-13 = {

      runtimes       = ["python3.13"]
      compatible_architectures = ["x86_64"]
    }
  }
}

