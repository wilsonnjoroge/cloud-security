data "aws_caller_identity" "current" {}

# Explicit key policy: the default policy only grants the account root
# user control over the key -- it does NOT let the CloudWatch Logs
# service itself use the key to encrypt log data. Without this, log
# group creation fails with "AccessDeniedException: The specified KMS
# key does not exist or is not allowed to be used", even though the key
# genuinely exists and Terraform's own IAM role can see it fine.

data "aws_iam_policy_document" "flowlogs_kms" {
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsUseOfKey"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.us-east-1.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_kms_key" "flowlogs" {
  description             = "KMS key for VPC Flow Logs CloudWatch logs"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.flowlogs_kms.json

  tags = {
    Name = "${var.project_name}-flowlogs-kms"
  }
}
