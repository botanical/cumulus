terraform {
  required_providers {
    aws = ">= 2.31.0"
  }
}

locals {
  lambda_log_group_name  = "/aws/lambda/${var.tea_egress_lambda_name}"
  tea_buckets            = concat(var.protected_buckets, var.public_buckets)

  built_lambda_source_file = "${path.module}/lambda.zip"
  repo_lambda_source_file = "${path.module}/../../packages/s3-credentials-endpoint/dist/lambda.zip"
  lambda_source_file = fileexists(local.built_lambda_source_file) ? local.built_lambda_source_file : local.repo_lambda_source_file
}

module "tea_map_cache" {
  prefix                     = var.prefix
  source                     = "../tea-map-cache"
  lambda_processing_role_arn = var.lambda_processing_role_arn
  tea_api_url                = var.tea_internal_api_endpoint
  tags                       = var.tags
  lambda_subnet_ids          = var.subnet_ids
  vpc_id                     = var.vpc_id
}

data "aws_lambda_invocation" "tea_map_cache" {
  depends_on                      = [module.tea_map_cache.lambda_function_name]
  function_name                   = module.tea_map_cache.lambda_function_name
  input                           = jsonencode({ bucketList = local.tea_buckets,
                                                 s3Bucket = var.system_bucket
                                                 s3Key = "${var.prefix}/distribution_bucket_map.json"
  })
}

data "aws_caller_identity" "current" {}

resource "aws_dynamodb_table" "access_tokens" {
  count = var.deploy_s3_credentials_endpoint ? 1 : 0

  name         = "${var.prefix}-s3-credentials-access-tokens"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "accessToken"

  attribute {
    name = "accessToken"
    type = "S"
  }

  tags = var.tags
}

data "aws_iam_policy_document" "assume_lambda_role" {
  count = var.deploy_s3_credentials_endpoint ? 1 : 0

  statement {
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "s3_credentials_lambda" {
  count = var.deploy_s3_credentials_endpoint ? 1 : 0

  name                 = "${var.prefix}-S3CredentialsLambda"
  assume_role_policy   = data.aws_iam_policy_document.assume_lambda_role[0].json
  permissions_boundary = var.permissions_boundary_arn
  tags                 = var.tags
}

data "aws_iam_policy_document" "s3_credentials_lambda" {
  count = var.deploy_s3_credentials_endpoint ? 1 : 0

  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [var.sts_credentials_lambda_function_arn]
  }

  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem"
    ]
    resources = [aws_dynamodb_table.access_tokens[0].arn]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "s3_credentials_lambda" {
  count  = var.deploy_s3_credentials_endpoint ? 1 : 0
  name   = "${var.prefix}_s3_credentials_lambda_policy"
  policy = data.aws_iam_policy_document.s3_credentials_lambda[0].json
  role   = aws_iam_role.s3_credentials_lambda[0].id
}

resource "aws_security_group" "s3_credentials_lambda" {
  count = (var.deploy_s3_credentials_endpoint && var.vpc_id != null) ? 1 : 0

  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}

resource "aws_lambda_function" "s3_credentials" {
  count = var.deploy_s3_credentials_endpoint ? 1 : 0

  function_name    = "${var.prefix}-s3-credentials-endpoint"
  filename         = local.lambda_source_file
  source_code_hash = filebase64sha256(local.lambda_source_file)
  handler          = "index.handler"
  role             = aws_iam_role.s3_credentials_lambda[0].arn
  runtime          = "nodejs12.x"
  timeout          = 10
  memory_size      = 320

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = (var.deploy_s3_credentials_endpoint && var.vpc_id != null) ? [aws_security_group.s3_credentials_lambda[0].id] : null
  }

  environment {
    variables = {
      DISTRIBUTION_ENDPOINT          = var.tea_external_api_endpoint
      DISTRIBUTION_REDIRECT_ENDPOINT = "${var.tea_external_api_endpoint}redirect"
      public_buckets                 = join(",", var.public_buckets)
      EARTHDATA_BASE_URL             = var.urs_url
      EARTHDATA_CLIENT_ID            = var.urs_client_id
      EARTHDATA_CLIENT_PASSWORD      = var.urs_client_password
      AccessTokensTable              = aws_dynamodb_table.access_tokens[0].id
      STSCredentialsLambda           = var.sts_credentials_lambda_function_arn
    }
  }
  tags = var.tags
}

data "aws_region" "current" {}

resource "aws_lambda_permission" "lambda_permission" {
  count         = var.deploy_s3_credentials_endpoint ? 1 : 0

  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_credentials[0].function_name
  principal     = "apigateway.amazonaws.com"

  # The /*/*/* part allows invocation from any stage, method and resource path
  # within API Gateway REST API.
  source_arn = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.tea_rest_api_id}/*/*/*"
}

# GET /s3credentials
resource "aws_api_gateway_resource" "s3_credentials" {
  count = var.deploy_s3_credentials_endpoint ? 1 : 0

  rest_api_id = var.tea_rest_api_id
  parent_id = var.tea_rest_api_root_resource_id
  path_part   = "s3credentials"
}

resource "aws_api_gateway_method" "s3_credentials" {
  count = var.deploy_s3_credentials_endpoint ? 1 : 0

  rest_api_id   = var.tea_rest_api_id
  resource_id   = aws_api_gateway_resource.s3_credentials[0].id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "s3_credentials" {
  count = var.deploy_s3_credentials_endpoint ? 1 : 0

  rest_api_id             = var.tea_rest_api_id
  resource_id             = aws_api_gateway_resource.s3_credentials[0].id
  http_method             = aws_api_gateway_method.s3_credentials[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.s3_credentials[0].invoke_arn
}

# GET /redirect
resource "aws_api_gateway_resource" "s3_credentials_redirect" {
  count = var.deploy_s3_credentials_endpoint ? 1 : 0

  rest_api_id = var.tea_rest_api_id
  parent_id = var.tea_rest_api_root_resource_id
  path_part   = "redirect"
}

resource "aws_api_gateway_method" "s3_credentials_redirect" {
  count = var.deploy_s3_credentials_endpoint ? 1 : 0

  rest_api_id   = var.tea_rest_api_id
  resource_id   = aws_api_gateway_resource.s3_credentials_redirect[0].id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "s3_credentials_redirect" {
  count = var.deploy_s3_credentials_endpoint ? 1 : 0

  rest_api_id             = var.tea_rest_api_id
  resource_id             = aws_api_gateway_resource.s3_credentials_redirect[0].id
  http_method             = aws_api_gateway_method.s3_credentials_redirect[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.s3_credentials[0].invoke_arn
}

# API deployment
resource "aws_api_gateway_deployment" "s3_credentials" {
  count = var.deploy_s3_credentials_endpoint ? 1 : 0

  depends_on = [
    aws_api_gateway_integration.s3_credentials_redirect[0],
    aws_api_gateway_integration.s3_credentials[0]
  ]

  rest_api_id = var.tea_rest_api_id
  stage_name  = var.tea_api_gateway_stage
}

# Egress Api Gateway Log Group Filter
resource "aws_cloudwatch_log_subscription_filter" "egress_api_gateway_log_subscription_filter" {
  count           = var.tea_api_egress_log_group != null ? 1 : 0
  name            = "${var.prefix}-EgressApiGatewayCloudWatchLogSubscriptionToSharedDestination"
  distribution    = "ByLogStream"
  destination_arn = var.log_destination_arn
  filter_pattern  = ""
  log_group_name  = var.tea_api_egress_log_group
}

# Egress Lambda Log Group
resource "aws_cloudwatch_log_group" "egress_lambda_log_group" {
  count             = var.log_destination_arn == null ? 0 : 1
  name              = local.lambda_log_group_name
  retention_in_days = 30
  tags              = var.tags
}

# Egress Lambda Log Group Filter
resource "aws_cloudwatch_log_subscription_filter" "egress_lambda_log_subscription_filter" {
  depends_on      = [aws_cloudwatch_log_group.egress_lambda_log_group]
  count           = var.log_destination_arn == null ? 0 : 1
  name            = "${var.prefix}-EgressLambdaLogSubscriptionToSharedDestination"
  destination_arn = var.log_destination_arn
  distribution    = "ByLogStream"
  filter_pattern  = ""
  log_group_name  = local.lambda_log_group_name
}
