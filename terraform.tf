terraform {
  required_version = ">=1.5.7" #originally made with 1.5.7
  required_providers {
    tls = "3.1.0"
  }
  # backend "local" {
  #   path = "test/terraform.tfstate"
  # }

  # backend "s3" {
  #   bucket = "my-tf-state-rcoding"
  #   key = "prod/myapp.tfstate"
  #   region = "us-east-1"

  #   encrypt = true
  #   dynamodb_table = "terraform-locks"
  # }

  # cloud {
  #   organization = "randallcoding"

  #   workspaces {
  #     name = "example-workspace"
  #   }
  # }

  backend "remote" {
    hostname = "app.terraform.io"
    organization = "randallcoding"

    workspaces {
      name = "example-workspace"
    }
  }
}