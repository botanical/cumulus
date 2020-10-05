# Required

variable "lambda_processing_role_arn" {
  type        = string
  description = "Cumulus lambda processing role"
}

variable "prefix" {
  type        = string
  description = "Resource prefix unique to this deployment"
}

variable "system_bucket" {
  type        = string
  description = "A bucket to be used for staging deployment files"
}

variable "tea_internal_api_endpoint" {
  description = "Thin Egress App internal endpoint URL"
  type        = string
}

# Optional

variable "deploy_s3_credentials_endpoint" {
  type    = bool
  default = true
}

variable "log_destination_arn" {
  type        = string
  default     = null
  description = "shared AWS:Log:Destination value. Requires log_api_gateway_to_cloudwatch set to true for TEA module."
}

variable "permissions_boundary_arn" {
  type        = string
  default     = null
  description = "The ARN of an IAM permissions boundary to use when creating IAM policies"
}

variable "protected_buckets" {
  type        = list(string)
  default     = []
  description = "A list of protected buckets"
}

variable "public_buckets" {
  type        = list(string)
  default     = []
  description = "A list of public buckets"
}

variable "sts_credentials_lambda_function_arn" {
  type    = string
  default = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "VPC subnets used by Lambda functions"
  default     = null
}

variable "tags" {
  description = "Tags to be applied to managed resources"
  type        = map(string)
  default     = {}
}

variable "tea_api_gateway_stage" {
  type        = string
  default     = null
  description = "The API Gateway stage name for the Thin Egress App"
}

variable "tea_api_egress_log_group" {
  description = "Thin Egress App API Gateway Cloudwatch log group ARN"
  type        = string
  default     = null
}

variable "tea_egress_lambda_name" {
  description = "Thin Egress App Egress Lambda name"
  type        = string
  default     = null
}

variable "tea_external_api_endpoint" {
  description = "Thin Egress App external endpoint URL"
  type        = string
  default     = null
}

variable "tea_rest_api_id" {
  description = "Thin Egress App API gateway ID"
  type        = string
  default     = null
}

variable "tea_rest_api_root_resource_id" {
  description = "Thin Egress App API gateway root resource ID"
  type        = string
  default     = null
}

variable "urs_client_id" {
  type        = string
  description = "The client ID for your Earthdata login (URS) application"
}

variable "urs_client_password" {
  type        = string
  description = "The client password for your Earthdata login (URS) application"
}

variable "urs_url" {
  type        = string
  default     = "https://urs.earthdata.nasa.gov"
  description = "The URL of the Earthdata Login site"
}

variable "vpc_id" {
  type        = string
  description = "VPC used by Lambda functions"
  default     = null
}
