output "public_ip" {
  value = aws_eip.lab.public_ip
}

output "instance_id" {
  value = aws_instance.lab.id
}

output "ssh_command" {
  value = "ssh ec2-user@${aws_eip.lab.public_ip}"
}
