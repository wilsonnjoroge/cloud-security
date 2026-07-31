output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "web_server_public_ip" {
  value = aws_instance.web.public_ip
}

output "web_url" {
  value = "http://${aws_instance.web.public_ip}"
}

output "ssh_command_web" {
  value = "ssh -i ${var.project_name}-key.pem ec2-user@${aws_instance.web.public_ip}"
}

output "app_server_private_ip" {
  value = aws_instance.app.private_ip
}

output "db_server_private_ip" {
  value = aws_instance.db.private_ip
}

output "pem_file_path" {
  description = "Where Terraform wrote the private key -- chmod 400 already applied"
  value       = local_sensitive_file.pem.filename
}
