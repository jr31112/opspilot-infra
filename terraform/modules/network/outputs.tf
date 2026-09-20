output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "public_subnet_ids" {
  value = {
    for az, subnet in aws_subnet.public_subnets :
    az => subnet.id
  }
}
