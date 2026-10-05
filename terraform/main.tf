# 1. Generador de sufijo aleatorio para evitar colisiones en IAM
resource "random_id" "role_suffix" {
  byte_length = 4
}

# 2. IAM Role para ejecución de la Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "serverless_lambda_exec_role_${random_id.role_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# 3. Permiso básico para que Lambda pueda escribir logs en CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "api_backend" {
  filename         = "../backend.zip"
  function_name    = "mobile_backend_api_${random_id.role_suffix.hex}"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = filebase64sha256("../backend.zip")

  environment {
    variables = {
      DATABASE_URL = var.database_url
      JWT_SECRET   = var.jwt_secret
    }
  }
}

# 5. Creación del API Gateway (HTTP API)
resource "aws_apigatewayv2_api" "http_api" {
  name          = "mobile_backend_gateway"
  protocol_type = "HTTP"
}

# 6. Integración entre API Gateway y Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.api_backend.invoke_arn
  integration_method = "POST"
}

# 7. Ruta comodín (Catch-all) para enviar todas las peticiones a la Lambda
resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# 8. Permiso para que API Gateway pueda invocar la Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# 9. Despliegue automático (Stage)
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}