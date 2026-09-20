variable "instances" {
  type = map(object({
    az            = string
    instance_type = string
  }))
}

variable "ami_id" {
  type = string
}

variable "subnet_ids" {
  type = map(string)
}

variable "security_group_ids" {
  type = list(string)
}
