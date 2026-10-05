# Generador de sufijo aleatorio para evitar colisiones de nombres en IAM
resource "random_id" "role_suffix" {
  byte_length = 4
}

# 1. IAM Role para Lambda
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

# Adjuntar política para que la Lambda pueda escribir logs en CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Crear el archivo backend.zip automáticamente desde la carpeta backend
data "archive_file" "backend_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../backend"
  output_path = "${path.module}/../backend.zip"
}

# 2. Función Lambda
resource "aws_lambda_function" "api_backend" {
  filename         = data.archive_file.backend_zip.output_path
  function_name    = "mobile_backend_api_${random_id.role_suffix.hex}"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.backend_zip.output_base64sha256

  environment {
    variables = {
      DATABASE_URL = var.database_url
      JWT_SECRET   = var.jwt_secret
    }
  }
}

# 3. API Gateway
resource "aws_apigatewayv2_api" "http_api" {
  name          = "mobile_backend_gateway_${random_id.role_suffix.hex}"
  protocol_type = "HTTP"
}

# 4. Stage por defecto para despliegue automático
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# 5. Integración API Gateway -> Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id             = aws_apigatewayv2_api.http_api.id
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.api_backend.invoke_arn
}

# 6. Rutas del API Gateway (Captura todo el tráfico)
resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# 7. Permiso para que API Gateway invoque la Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_backend.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}