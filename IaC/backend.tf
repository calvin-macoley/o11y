# Remote state, backed by the Garage cluster deployed in
# homelab-gitops/s3-garage (endpoint http://192.168.1.57:3900, region "garage").
#
# Bucket + access key must already exist in Garage:
#   garage bucket create o11y-tfstate
#   garage key create o11y-tfstate
#   garage bucket allow --read --write --owner o11y-tfstate --key o11y-tfstate
#
# Credentials are picked up from the standard AWS_ACCESS_KEY_ID /
# AWS_SECRET_ACCESS_KEY env vars at `tofu init` time — never hardcoded here.
terraform {
  backend "s3" {
    bucket = "o11y-tfstate"
    key    = "o11y/terraform.tfstate"
    region = "garage"

    endpoints = {
      s3 = "http://192.168.1.57:3900"
    }

    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
