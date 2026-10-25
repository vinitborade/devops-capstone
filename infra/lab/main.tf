# ---------- 1. Look things up (data sources read, they don't create) ----------

# The latest Amazon Linux 2023 image ID, published by AWS in Parameter Store.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# The default VPC (network) every new AWS account already has.
data "aws_vpc" "default" {
  default = true
}

# ---------- 2. SSH key ----------

resource "aws_key_pair" "lab" {
  key_name   = "devops-lab"
  public_key = file(pathexpand(var.public_key_path))
}

# ---------- 3. Firewall (security group) ----------

locals {
  # name = port. Every port is opened ONLY to your IP.
  open_ports = {
    ssh          = 22
    http         = 80   # kind Ingress (Day 7)
    app          = 8000 # orders-api
    splunk       = 8001 # Day 12
    jenkins      = 8080 # Day 10
    grafana      = 3000 # Day 13
    prometheus   = 9090 # Day 13
    alertmanager = 9093 # Day 13
  }
}

resource "aws_security_group" "lab" {
  name        = "devops-lab-sg"
  description = "Lab server: open only to my IP"
  vpc_id      = data.aws_vpc.default.id
}

# One inbound rule per port (for_each creates one copy per item in the map).
resource "aws_vpc_security_group_ingress_rule" "lab" {
  for_each          = local.open_ports
  security_group_id = aws_security_group.lab.id
  description       = each.key
  cidr_ipv4         = var.my_ip
  from_port         = each.value
  to_port           = each.value
  ip_protocol       = "tcp"
}

# Outbound: the server may reach the internet (to download packages).
resource "aws_vpc_security_group_egress_rule" "all_out" {
  security_group_id = aws_security_group.lab.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------- 4. IAM role: permissions the server borrows ----------

# "Trust policy": only the EC2 service may use this role.
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lab" {
  name               = "devops-lab-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Lets you open a browser terminal from the AWS console (Session Manager) as a backup.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.lab.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Lab only: the server can build VPCs, EKS, ECR etc. on later days.
# In a company you would grant only what is needed (least privilege).
resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.lab.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# An EC2 server can't hold a role directly; it holds an "instance profile" that wraps the role.
resource "aws_iam_instance_profile" "lab" {
  name = "devops-lab-profile"
  role = aws_iam_role.lab.name
}

# ---------- 5. The server ----------

resource "aws_instance" "lab" {
  ami                    = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type          = var.instance_type
  key_name               = aws_key_pair.lab.key_name
  vpc_security_group_ids = [aws_security_group.lab.id]
  iam_instance_profile   = aws_iam_instance_profile.lab.name
  user_data              = file("${path.module}/user_data.sh") # runs once at first boot

  # IMDSv2 only: a safer way for the server to read its own metadata and role credentials.
  # hop limit 2 lets containers on the server reach it too.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "devops-lab"
  }

  # Don't rebuild the server just because AWS published a newer image or we edit the script.
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ---------- 6. Fixed public IP ----------

resource "aws_eip" "lab" {
  instance = aws_instance.lab.id
  domain   = "vpc"

  tags = {
    Name = "devops-lab-eip"
  }
}
