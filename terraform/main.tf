# Generador de sufijo aleatorio para evitar colisiones de nombres en IAM
resource "random_id" "role_suffix" {
  byte_length = 4
}

# 1. IAM Role para Lambda Principal
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

# Adjuntar política para logs de CloudWatch
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

# 2. Función Lambda Principal (Backend)
resource "aws_lambda_function" "api_backend" {
  filename         = data.archive_file.backend_zip.output_path
  function_name    = "mobile_backend_api_${random_id.role_suffix.hex}"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.backend_zip.output_base64sha256

  environment {
    variables = {
      DATABASE_URL  = var.database_url
      JWT_SECRET    = var.jwt_secret
      SNS_TOPIC_ARN = aws_sns_topic.notifications_topic.arn
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

# 6. Rutas del API Gateway
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

# ==========================================
# NUEVA ARQUITECTURA: SNS, SQS Y NOTIFICACIONES
# ==========================================

# Tópico SNS
resource "aws_sns_topic" "notifications_topic" {
  name = "notifications_topic_${random_id.role_suffix.hex}"
}

# Cola SQS
resource "aws_sqs_queue" "notifications_queue" {
  name = "notifications_queue_${random_id.role_suffix.hex}"
}

# Suscripción SNS -> SQS
resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.notifications_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.notifications_queue.arn
}

# Política para permitir que SNS envíe mensajes a SQS
resource "aws_sqs_queue_policy" "sqs_policy" {
  queue_url = aws_sqs_queue.notifications_queue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "sns.amazonaws.com"
      }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.notifications_queue.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_sns_topic.notifications_topic.arn
        }
      }
    }]
  })
}

# Rol IAM para la Lambda de Notificaciones
resource "aws_iam_role" "notification_lambda_exec" {
  name = "notification_lambda_role_${random_id.role_suffix.hex}"

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

resource "aws_iam_role_policy_attachment" "notif_lambda_logs" {
  role       = aws_iam_role.notification_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "notif_lambda_sqs" {
  role       = aws_iam_role.notification_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

# Empaquetar la nueva Lambda de Notificaciones
data "archive_file" "notification_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../notification-lambda"
  output_path = "${path.module}/../notification-lambda.zip"
}

resource "aws_lambda_function" "notification_lambda" {
  filename         = data.archive_file.notification_zip.output_path
  function_name    = "notification-lambda-${random_id.role_suffix.hex}"
  role             = aws_iam_role.notification_lambda_exec.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.notification_zip.output_base64sha256
}

# Event Source Mapping: SQS activa la Lambda de Notificaciones
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.notifications_queue.arn
  function_name    = aws_lambda_function.notification_lambda.arn
  enabled          = true
  batch_size       = 5
}

# Permiso para que la Lambda Principal pueda publicar en SNS
resource "aws_iam_policy" "lambda_sns_publish" {
  name = "lambda_sns_publish_${random_id.role_suffix.hex}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.notifications_topic.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "main_lambda_sns_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_sns_publish.arn
}