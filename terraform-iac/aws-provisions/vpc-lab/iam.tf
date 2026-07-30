data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# Custom policy: lab2-s3-readonly-policy
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "lab2_s3_readonly" {
  name        = "lab2-s3-readonly-policy"
  description = "Read-only access to lab2-* S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ReadOnly"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::lab2-*",
          "arn:aws:s3:::lab2-*/*"
        ]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Web server role: SSM + CloudWatch agent + custom S3 read-only policy
# ---------------------------------------------------------------------------
resource "aws_iam_role" "web_server" {
  name               = "lab2-web-server-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "web_ssm" {
  role       = aws_iam_role.web_server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "web_cloudwatch" {
  role       = aws_iam_role.web_server.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "web_s3_readonly" {
  role       = aws_iam_role.web_server.name
  policy_arn = aws_iam_policy.lab2_s3_readonly.arn
}

resource "aws_iam_instance_profile" "web_server" {
  name = "lab2-web-server-role"
  role = aws_iam_role.web_server.name
}

# ---------------------------------------------------------------------------
# App server role: SSM only
# ---------------------------------------------------------------------------
resource "aws_iam_role" "app_server" {
  name               = "lab2-app-server-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app_server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_server" {
  name = "lab2-app-server-role"
  role = aws_iam_role.app_server.name
}

# ---------------------------------------------------------------------------
# DB server role: SSM only
# ---------------------------------------------------------------------------
resource "aws_iam_role" "db_server" {
  name               = "lab2-db-server-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "db_ssm" {
  role       = aws_iam_role.db_server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "db_server" {
  name = "lab2-db-server-role"
  role = aws_iam_role.db_server.name
}
