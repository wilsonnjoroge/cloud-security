# ---------------------------------------------------------------------------
# Web tier SG: HTTP/HTTPS from anywhere, SSH from your IP only.
# ---------------------------------------------------------------------------
resource "aws_security_group" "web" {
  name        = "${var.project_name}-Web-Server-SG"
  description = "Web tier: HTTP/HTTPS public, SSH from admin IP only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-Web-Server-SG"
  }
}

# ---------------------------------------------------------------------------
# App tier SG: only reachable from the Web tier SG, on port 5050.
# ---------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${var.project_name}-App-Server-SG"
  description = "App tier: reachable only from the web tier on 5050"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "App traffic from web tier"
    from_port       = 5050
    to_port         = 5050
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-App-Server-SG"
  }
}

# ---------------------------------------------------------------------------
# DB tier SG: only reachable from the App tier SG, on port 3306 (simulated
# MySQL).
# ---------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.project_name}-Db-Server-SG"
  description = "DB tier: reachable only from the app tier on 3306"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "DB traffic from app tier"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-Db-Server-SG"
  }
}

# ---------------------------------------------------------------------------
# VPC endpoints SG: HTTPS (443) from the app and db tiers only. Attached to
# the interface endpoints (ssm, ssmmessages, ec2messages) in vpc_endpoints.tf.
# ---------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-VPC-Endpoints-Server-SG"
  description = "VPC endpoints: HTTPS from app and db tiers only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTPS from app tier"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "HTTPS from db tier"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.db.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-VPC-Endpoints-Server-SG"
  }
}
