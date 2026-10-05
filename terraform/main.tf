# Generador de sufijo aleatorio para evitar colisiones de nombres en IAM
resource "random_id" "role_suffix" {
  byte_length = 4
}

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