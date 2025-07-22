variable "services" {
  type = list(string)
  default = ["service-a", "service-b"]
}

variable "location" {
  default = "Southeast Asia"
}

variable "resource_group_name" {
  default = "ai51foldsrg"
}

variable "acr_name" {
  default = "ai51foldsacr"  
}
variable "env_name" {
  default = "ai51foldsenv"  
}
