module "network" {
  source = "../../modules/network"

  vpc_cidr       = var.vpc_cidr
  vpc_name       = var.vpc_name
  public_subnets = var.public_subnets
}

module "security" {
  source = "../../modules/security"

  vpc_id  = module.network.vpc_id
  sg_name = var.sg_name
}

module "compute" {
  source = "../../modules/compute"

  instances  = var.instances
  ami_id     = var.ami_id
  subnet_ids = module.network.public_subnet_ids

  security_group_ids = [
    module.security.sg_id
  ]
}
