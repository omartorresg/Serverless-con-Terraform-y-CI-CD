output "api_gateway_url" {
  description = "URL base para consumir desde la Mobile App"
  value       = aws_apigatewayv2_api.http_api.api_endpoint
}