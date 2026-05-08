# terraform/backend.tf  ← create this separately, don't commit it
terraform {
  backend "s3" {
    bucket         = "my-tf-state-bucket"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-lock"
    encrypt        = true
  }
}