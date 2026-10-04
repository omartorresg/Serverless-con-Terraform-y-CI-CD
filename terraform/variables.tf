variable "aws_region" {
  description = "La región de AWS"
  type        = string
  default     = "us-east-1"
}

variable "database_url" {
  description = "URL de conexión a la base de datos Cloud"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "Secreto para firmar los tokens JWT"
  type        = string
  sensitive   = true
}