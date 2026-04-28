terraform {
  backend "azurerm" {
    # Values are supplied via bootstrap.sh output or -backend-config flags.
    # Example:
    #   terraform init \
    #     -backend-config="resource_group_name=rpi-arc-tfstate-rg" \
    #     -backend-config="storage_account_name=rpiarctf<suffix>" \
    #     -backend-config="container_name=tfstate" \
    #     -backend-config="key=terraform.tfstate"
    environment = "usgovernment"
  }
}
