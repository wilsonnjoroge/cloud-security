variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "public_az" {
  description = "AZ for the public subnet"
  type        = string
  default     = "us-east-1a"
}

variable "private_az" {
  description = "AZ for the private subnet"
  type        = string
  default     = "us-east-1b"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.10.2.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.10.1.0/24"
}

variable "my_ip_cidr" {
  description = <<-EOT
    Your public IP in CIDR form, e.g. "1.2.3.4/32".
    Used for SSH access to the web server SG and the public NACL.
    Find yours with: curl -s https://checkip.amazonaws.com
  EOT
  type        = string
  sensitive   = true
  # No default on purpose -- you must supply the public IP.
}

variable "instance_type" {
  description = "EC2 instance type, used for all three tiers"
  type        = string
  default     = "t3.micro"
}

variable "project_name" {
  description = "Prefix used for naming/tagging resources"
  type        = string
  default     = "lab2"
}
