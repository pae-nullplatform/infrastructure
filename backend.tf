terraform {
  backend "s3" {
    bucket  = "tf-state-6ea6060303e5f50a"
    key     = "infra/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
    profile = "providers-test"
  }
}