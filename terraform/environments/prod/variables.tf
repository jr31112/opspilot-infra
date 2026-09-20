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

variable "sg_name" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "instances" {
  type = map(object({
    az            = string
    instance_type = string
  }))
}

variable "security_group_ids" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}
