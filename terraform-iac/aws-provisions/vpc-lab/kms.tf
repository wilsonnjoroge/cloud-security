
resource "aws_kms_key" "flowlogs" {
  description             = "KMS key for VPC Flow Logs CloudWatch logs"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = {
    Name = "${var.project_name}-flowlogs-kms"
  }
}