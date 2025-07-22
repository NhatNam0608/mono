terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.86.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "595c6b06-637c-4461-af34-72506690001c"
}

locals {
  service_ports = {
    service-a = 8080
    service-b = 8081
  }
  
  # Validate all services have port mappings
  validated_services = [
    for service in var.services : service
    if contains(keys(local.service_ports), service)
  ]
  
  # Convert service names for docker (replace hyphens with underscores for local images)
  local_image_names = {
    for service in local.validated_services :
    service => replace(service, "-", "_")
  }
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# ✅ THÊM: Data source để lấy ACR credentials
data "azurerm_container_registry" "acr" {
  name                = azurerm_container_registry.acr.name
  resource_group_name = azurerm_resource_group.rg.name
  depends_on          = [azurerm_container_registry.acr]
}

# ✅ Login to ACR và push images using Docker CLI
resource "null_resource" "docker_push" {
  for_each = toset(local.validated_services)

  # Triggers để rebuild khi có thay đổi
  triggers = {
    acr_server    = data.azurerm_container_registry.acr.login_server
    service_name  = each.key
    local_image   = "${local.local_image_names[each.key]}:latest"
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Login to ACR
      docker login ${data.azurerm_container_registry.acr.login_server} -u ${data.azurerm_container_registry.acr.admin_username} -p ${data.azurerm_container_registry.acr.admin_password}
      
      # Tag image for ACR
      docker tag ${local.local_image_names[each.key]}:latest ${data.azurerm_container_registry.acr.login_server}/${each.key}:latest
      
      # Push to ACR
      docker push ${data.azurerm_container_registry.acr.login_server}/${each.key}:latest
    EOT

    interpreter = ["PowerShell", "-Command"]
  }

  depends_on = [azurerm_container_registry.acr]
}

resource "azurerm_container_app_environment" "env" {
  name                = var.env_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_container_app" "app" {
  for_each = toset(local.validated_services)

  name                         = each.key
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode               = "Single"

  template {
    container {
      name   = each.key
      image  = "${azurerm_container_registry.acr.login_server}/${each.key}:latest"
      cpu    = 0.5
      memory = "1.0Gi"
      
      env {
        name  = "PORT"
        value = tostring(local.service_ports[each.key])
      }
    }
    
    min_replicas = 1
    max_replicas = 2
  }

  identity {
    type = "SystemAssigned"
  }

  # Registry credentials với secret
  secret {
    name  = "acr-password"
    value = azurerm_container_registry.acr.admin_password
  }

  registry {
    server               = azurerm_container_registry.acr.login_server
    username             = azurerm_container_registry.acr.admin_username
    password_secret_name = "acr-password"
  }

  ingress {
    external_enabled = true
    target_port      = local.service_ports[each.key]
    transport        = "auto"
    
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  # ✅ THÊM: Đảm bảo images được push trước khi deploy
  depends_on = [
    null_resource.docker_push
  ]
}