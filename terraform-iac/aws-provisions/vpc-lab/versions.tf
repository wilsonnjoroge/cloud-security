terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # No profile set here on purpose -- Terraform will read AWS_PROFILE from
  # the shell it's run in. Hardcoding a profile here would silently override
  # whatever profile you've exported, which is a common source of "it
  # deployed to the wrong account" surprises.
}
