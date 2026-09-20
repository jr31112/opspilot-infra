variable "vpc_cidr" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "public_subnets" {
  type = map(object({
    cidr   = string
    number = number
  }))
}
