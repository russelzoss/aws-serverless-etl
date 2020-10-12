terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "3.10.0"
    }
  }
}

provider "aws" {
  profile = "default"
  region = var.region
}

data "aws_caller_identity" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket" "partner_bucket" {
  bucket = var.bucket
  acl    = "private"

  tags = {
    Name        = "Partner bucket"
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.partner_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.partner_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

resource "aws_sqs_queue" "partner-queue" {
  name = var.queue
  fifo_queue = true
  content_based_deduplication = true
}

resource "aws_iam_role" "role" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
}
EOF
}

resource "aws_iam_policy" "policy_sqs" {
  name        = "sqs_write"
  path        = "/"
  description = "SQS write policy"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "sqs:DeleteMessage",
                "sqs:ChangeMessageVisibility",
                "sqs:DeleteMessageBatch",
                "sqs:SendMessageBatch",
                "sqs:PurgeQueue",
                "sqs:DeleteQueue",
                "sqs:SendMessage",
                "sqs:CreateQueue",
                "sqs:ChangeMessageVisibilityBatch",
                "sqs:SetQueueAttributes",
                "sqs:GetQueueUrl"
            ],
            "Resource": "arn:aws:sqs:eu-central-1:${data.aws_caller_identity.current.account_id}:${var.queue}"
        }
    ]
}
EOF
}

resource "aws_iam_policy" "policy_s3" {
  name        = "s3_bucket_read"
  path        = "/"
  description = "S3 bucket read policy"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::${var.bucket}",
                "arn:aws:s3:::${var.bucket}/*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_policy" "policy_logs" {
  name        = "lambda_write_logs"
  path        = "/"
  description = "Lambda write logs"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "aim_for_lambda_sqs" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.policy_sqs.arn
}

resource "aws_iam_role_policy_attachment" "aim_for_lambda_s3" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.policy_s3.arn
}

resource "aws_iam_role_policy_attachment" "aim_for_lambda_logs" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.policy_logs.arn
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.partner_lambda.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.partner_bucket.arn
}

resource "aws_lambda_function" "partner_lambda" {
  filename      = "function.zip"
  function_name = "partner-data-import"
  role          = aws_iam_role.role.arn
  handler       = "lambda_function.lambda_handler"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("function.zip")

  runtime = "python3.8"

}