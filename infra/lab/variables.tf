# Inputs: values you can change without editing the main code.

variable "region" {
  type    = string
  default = "ap-south-1" # Mumbai
}

variable "instance_type" {
  type    = string
  default = "t3.large" # 2 vCPU, 8 GB RAM
}

variable "volume_size" {
  type    = number
  default = 40 # GB
}

variable "my_ip" {
  type        = string
  description = "Your home public IP in CIDR form, e.g. 203.0.113.25/32"
}

variable "public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}
