resource "aws_security_group" "sg" {
  name        = var.sg_name
  vpc_id      = var.vpc_id
  description = "default VPC security group"
}
