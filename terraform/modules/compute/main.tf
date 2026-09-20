resource "aws_instance" "ec2" {
  for_each = var.instances

  ami                         = var.ami_id
  instance_type               = each.value.instance_type
  subnet_id                   = var.subnet_ids[each.value.az]
  vpc_security_group_ids      = var.security_group_ids
  associate_public_ip_address = true
  key_name                    = "opsPilot"
}
