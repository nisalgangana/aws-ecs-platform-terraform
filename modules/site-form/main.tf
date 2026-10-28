# Contact and dealer forms of a static site:
# CloudFront /api/* -> Lambda function URL (AWS_IAM, signed by CloudFront OAC) -> SNS -> e-mail

# Zipped during plan; the Terraform pipeline passes .build/ from the plan step to the apply step
data "archive_file" "code" {
  type        = "zip"
  source_file = "${path.module}/src/index.mjs"
  output_path = "${path.module}/.build/site-form.zip"
}

resource "aws_sns_topic" "enquiries" {
  name              = "${var.name_prefix}-site-enquiries"
  kms_master_key_id = "alias/aws/sns" # enquiries hold names and phone numbers
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.notify_emails)

  topic_arn = aws_sns_topic.enquiries.arn
  protocol  = "email"
  endpoint  = each.value
}

# Created here, not by Lambda, so it gets a retention period
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name_prefix}-site-form"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name_prefix}-site-form-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  statement {
    sid       = "Notify"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.enquiries.arn]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "site-form"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

resource "aws_lambda_function" "this" {
  function_name    = "${var.name_prefix}-site-form"
  role             = aws_iam_role.this.arn
  runtime          = "nodejs22.x"
  architectures    = ["arm64"]
  handler          = "index.handler"
  filename         = data.archive_file.code.output_path
  source_code_hash = data.archive_file.code.output_base64sha256
  memory_size      = 128
  timeout          = 10

  environment {
    variables = {
      TOPIC_ARN = aws_sns_topic.enquiries.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.this, aws_iam_role_policy.this]
}

# AWS_IAM: unsigned requests get 403. Only CloudFront (OAC) can call it.
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  authorization_type = "AWS_IAM"
}
