terraform {
  required_providers {
    aws  = ">= 3.5.0"
    null = "~> 2.1"
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  ignore_tags {
    key_prefixes = ["gsfc-ngap"]
  }
}

provider "aws" {
  alias   = "usw2"
  region  = "us-west-2"
  profile = var.aws_profile
}

locals {
  tags = merge(var.tags, { Deployment = var.prefix })
  elasticsearch_alarms            = lookup(data.terraform_remote_state.data_persistence.outputs, "elasticsearch_alarms", [])
  elasticsearch_domain_arn        = lookup(data.terraform_remote_state.data_persistence.outputs, "elasticsearch_domain_arn", null)
  elasticsearch_hostname          = lookup(data.terraform_remote_state.data_persistence.outputs, "elasticsearch_hostname", null)
  elasticsearch_security_group_id = lookup(data.terraform_remote_state.data_persistence.outputs, "elasticsearch_security_group_id", "")
  rds_security_group              = lookup(data.terraform_remote_state.data_persistence.outputs, "rds_security_group", "")
  rds_credentials_secret_arn      = lookup(data.terraform_remote_state.data_persistence.outputs, "database_credentials_secret_arn", "")

  protected_bucket_names = [for k, v in var.buckets : v.name if v.type == "protected"]
  public_bucket_names    = [for k, v in var.buckets : v.name if v.type == "public"]

  tea_stage_name = "DEV"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "terraform_remote_state" "data_persistence" {
  backend   = "s3"
  config    = var.data_persistence_remote_state_config
  workspace = terraform.workspace
}

data "aws_lambda_function" "sts_credentials" {
  function_name = "gsfc-ngap-sh-s3-sts-get-keys"
}

data "aws_ssm_parameter" "ecs_image_id" {
  name = "image_id_ecs_amz2"
}

module "cumulus" {
  source = "../../tf-modules/cumulus"

  cumulus_message_adapter_lambda_layer_arn = var.cumulus_message_adapter_lambda_layer_arn

  prefix = var.prefix

  deploy_to_ngap = true

  bucket_map_key = var.bucket_map_key

  vpc_id            = var.vpc_id
  lambda_subnet_ids = var.lambda_subnet_ids

  rds_security_group            = local.rds_security_group
  rds_user_access_secret_arn    = local.rds_credentials_secret_arn
  rds_connection_heartbeat      = var.rds_connection_heartbeat

  ecs_cluster_instance_image_id   = data.aws_ssm_parameter.ecs_image_id.value
  ecs_cluster_instance_subnet_ids = (length(var.ecs_cluster_instance_subnet_ids) == 0
    ? var.lambda_subnet_ids
    : var.ecs_cluster_instance_subnet_ids
  )
  ecs_cluster_min_size            = 2
  ecs_cluster_desired_size        = 2
  ecs_cluster_max_size            = 3
  key_name                        = var.key_name

  urs_url             = "https://uat.urs.earthdata.nasa.gov"
  urs_client_id       = var.urs_client_id
  urs_client_password = var.urs_client_password

  ems_host              = var.ems_host
  ems_port              = var.ems_port
  ems_path              = var.ems_path
  ems_datasource        = var.ems_datasource
  ems_private_key       = var.ems_private_key
  ems_provider          = var.ems_provider
  ems_retention_in_days = var.ems_retention_in_days
  ems_submit_report     = var.ems_submit_report
  ems_username          = var.ems_username

  metrics_es_host     = var.metrics_es_host
  metrics_es_password = var.metrics_es_password
  metrics_es_username = var.metrics_es_username

  cmr_client_id   = var.cmr_client_id
  cmr_environment = "UAT"
  cmr_username    = var.cmr_username
  cmr_password    = var.cmr_password
  cmr_provider    = var.cmr_provider

  cmr_oauth_provider = var.cmr_oauth_provider

  launchpad_api         = var.launchpad_api
  launchpad_certificate = var.launchpad_certificate
  launchpad_passphrase  = var.launchpad_passphrase

  oauth_provider   = var.oauth_provider
  oauth_user_group = var.oauth_user_group

  saml_entity_id                  = var.saml_entity_id
  saml_assertion_consumer_service = var.saml_assertion_consumer_service
  saml_idp_login                  = var.saml_idp_login
  saml_launchpad_metadata_url     = var.saml_launchpad_metadata_url

  permissions_boundary_arn = var.permissions_boundary_arn

  system_bucket = var.system_bucket
  buckets       = var.buckets

  elasticsearch_alarms            = local.elasticsearch_alarms
  elasticsearch_domain_arn        = local.elasticsearch_domain_arn
  elasticsearch_hostname          = local.elasticsearch_hostname
  elasticsearch_security_group_id = local.elasticsearch_security_group_id
  es_index_shards                 = var.es_index_shards

  dynamo_tables = data.terraform_remote_state.data_persistence.outputs.dynamo_tables

  # Archive API settings
  token_secret = var.token_secret
  archive_api_users = [
    "chuckwondo",
    "jennyhliu",
    "jmcampbell",
    "kbaynes",
    "kkelly",
    "kovarik",
    "lfrederick",
    "matthewsavoie",
    "mboyd",
    "menno.vandiermen",
    "mhuffnagle2",
    "brian.tennity",
    "jasmine"
  ]
  archive_api_port              = var.archive_api_port
  private_archive_api_gateway   = var.private_archive_api_gateway
  api_gateway_stage             = var.api_gateway_stage

  # Thin Egress App settings
  # must match stage_name variable for thin-egress-app module
  tea_api_gateway_stage = local.tea_stage_name

  tea_rest_api_id = module.thin_egress_app.rest_api.id
  tea_rest_api_root_resource_id = module.thin_egress_app.rest_api.root_resource_id
  tea_internal_api_endpoint = module.thin_egress_app.internal_api_endpoint
  tea_external_api_endpoint = module.thin_egress_app.api_endpoint
  tea_api_egress_log_group = module.thin_egress_app.egress_log_group

  log_destination_arn = var.log_destination_arn

  # S3 credentials endpoint
  sts_credentials_lambda_function_arn = data.aws_lambda_function.sts_credentials.arn

  additional_log_groups_to_elk  = var.additional_log_groups_to_elk

  tags = local.tags
}

resource "aws_secretsmanager_secret" "thin_egress_urs_creds" {
  name_prefix = "${var.prefix}-tea-urs-creds-"
  description = "URS credentials for the ${var.prefix} Thin Egress App"
  tags        = local.tags
}

resource "aws_secretsmanager_secret_version" "thin_egress_urs_creds" {
  secret_id     = aws_secretsmanager_secret.thin_egress_urs_creds.id
  secret_string = jsonencode({
    UrsId       = var.urs_client_id
    UrsAuth     = base64encode("${var.urs_client_id}:${var.urs_client_password}")
  })
}

resource "aws_s3_bucket_object" "bucket_map_yaml" {
  bucket  = var.system_bucket
  key     = "${var.prefix}/thin-egress-app/bucket_map.yaml"
  content = templatefile("${path.module}/thin-egress-app/bucket_map.yaml.tmpl", {
    protected_buckets = local.protected_bucket_names,
    public_buckets = local.public_bucket_names
  })
  etag    = md5(templatefile("${path.module}/thin-egress-app/bucket_map.yaml.tmpl", {
    protected_buckets = local.protected_bucket_names,
    public_buckets = local.public_bucket_names
  }))
  tags    = var.tags
}

module "thin_egress_app" {
  source = "s3::https://s3.amazonaws.com/asf.public.code/thin-egress-app/tea-terraform-build.97.zip"

  auth_base_url              = "https://uat.urs.earthdata.nasa.gov"
  bucket_map_file            = aws_s3_bucket_object.bucket_map_yaml.id
  bucketname_prefix          = ""
  config_bucket              = var.system_bucket
  domain_name                = var.distribution_url == null ? null : replace(replace(var.distribution_url, "/^https?:///", ""), "//$/", "")
  jwt_secret_name            = var.thin_egress_jwt_secret_name
  permissions_boundary_name  = var.permissions_boundary_arn == null ? null : reverse(split("/", var.permissions_boundary_arn))[0]
  private_vpc                = var.vpc_id
  stack_name                 = "${var.prefix}-thin-egress-app"
  stage_name                 = local.tea_stage_name
  urs_auth_creds_secret_name = aws_secretsmanager_secret.thin_egress_urs_creds.name
  vpc_subnet_ids             = var.lambda_subnet_ids
}

resource "aws_security_group" "no_ingress_all_egress" {
  name   = "${var.prefix}-cumulus-tf-no-ingress-all-egress"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_sns_topic_subscription" "sns_s3_executions_test" {
  topic_arn = module.cumulus.report_executions_sns_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.sns_s3_executions_test.arn
}

resource "aws_lambda_permission" "sns_s3_executions_test" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sns_s3_executions_test.arn
  principal     = "sns.amazonaws.com"
  source_arn    = module.cumulus.report_executions_sns_topic_arn
}

resource "aws_sns_topic_subscription" "sns_s3_granules_test" {
  topic_arn = module.cumulus.report_granules_sns_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.sns_s3_granules_test.arn
}

resource "aws_lambda_permission" "sns_s3_granules_test" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sns_s3_granules_test.arn
  principal     = "sns.amazonaws.com"
  source_arn    = module.cumulus.report_granules_sns_topic_arn
}

resource "aws_sns_topic_subscription" "sns_s3_pdrs_test" {
  topic_arn = module.cumulus.report_pdrs_sns_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.sns_s3_pdrs_test.arn
}

resource "aws_lambda_permission" "sns_s3_pdrs_test" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sns_s3_pdrs_test.arn
  principal     = "sns.amazonaws.com"
  source_arn    = module.cumulus.report_pdrs_sns_topic_arn
}

resource "aws_sns_topic_subscription" "sns_s3_collections_test" {
  topic_arn = module.cumulus.report_collections_sns_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.sns_s3_collections_test.arn
}

resource "aws_lambda_permission" "sns_s3_collections_test" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sns_s3_collections_test.arn
  principal     = "sns.amazonaws.com"
  source_arn    = module.cumulus.report_collections_sns_topic_arn
}

module "s3_access_test_lambda" {
  source = "./modules/s3_access_test"

  prefix                     = var.prefix
  lambda_processing_role_arn = module.cumulus.lambda_processing_role_arn

  providers = {
    aws = "aws.usw2"
  }

  tags = local.tags
}
