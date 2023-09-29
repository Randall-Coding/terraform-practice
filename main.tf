# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

#Retrieve the list of AZs in the current AWS region
data "aws_availability_zones" "available" {}
data "aws_region" "current" {}

locals {
  team        = "api_mgmt_dev"
  application = "corp_api"
  serve_name  = "ec2-${var.environment}-api-${var.variables_sub_az}"
}

resource "tls_private_key" "generated" {
  algorithm = "RSA"
}
resource "local_file" "private_key_pem" {
  content  = tls_private_key.generated.private_key_pem
  filename = "MyAWSKey.pem"
}

resource "aws_key_pair" "developer" {
  key_name   = "developer-${var.environment}"
  public_key = tls_private_key.generated.public_key_openssh

  lifecycle {
    ignore_changes = [key_name]
  }
}

#Define the VPC
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = var.vpc_name
    Environment = var.environment
    Terraform   = "true"
    Region      = data.aws_region.current.name
  }

  enable_dns_hostnames = true
}

#Deploy the private subnets
resource "aws_subnet" "private_subnets" {
  for_each   = var.private_subnets
  vpc_id     = aws_vpc.vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value)
  availability_zone = tolist(data.aws_availability_zones.available.names)[
  each.value]
  tags = {
    Name      = each.key
    Terraform = "true"
  }
}
#Deploy the public subnets
resource "aws_subnet" "public_subnets" {
  for_each   = var.public_subnets
  vpc_id     = aws_vpc.vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value + 100)
  availability_zone = tolist(data.aws_availability_zones.available.
  names)[each.value]
  map_public_ip_on_launch = true
  tags = {
    Name      = each.key
    Terraform = "true"
  }
}
#Create route tables for public and private subnets
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
    #nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "demo_public_rtb"
    Terraform = "true"
  }
}
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    # gateway_id = aws_internet_gateway.internet_gateway.id
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
  tags = {
    Name      = "demo_private_rtb"
    Terraform = "true"
  }
}
#Create route table associations
resource "aws_route_table_association" "public" {
  depends_on     = [aws_subnet.public_subnets]
  route_table_id = aws_route_table.public_route_table.id
  for_each       = aws_subnet.public_subnets
  subnet_id      = each.value.id
}
resource "aws_route_table_association" "private" {
  depends_on     = [aws_subnet.private_subnets]
  route_table_id = aws_route_table.private_route_table.id
  for_each       = aws_subnet.private_subnets
  subnet_id      = each.value.id
}
#Create Internet Gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "demo_igw"
  }
}
#Create EIP for NAT Gateway
resource "aws_eip" "nat_gateway_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.internet_gateway]
  tags = {
    Name = "demo_igw_eip"
  }
}
#Create NAT Gateway
resource "aws_nat_gateway" "nat_gateway" {
  depends_on    = [aws_subnet.public_subnets]
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = aws_subnet.public_subnets["public_subnet_1"].id
  tags = {
    Name = "demo_nat_gateway"
  }
}

# Terraform Data Block - To Lookup Latest Ubuntu 20.04 AMI Image
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}

# Terraform Resource Block - To Build EC2 instance in Public Subnet
resource "aws_instance" "web_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnets["public_subnet_1"].id
  tags = {
    Name  = local.serve_name
    Owner = local.team
    App   = local.application
  }
  key_name               = aws_key_pair.developer.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh.id, aws_security_group.allow_web.id]
}

resource "aws_security_group" "allow_web" {
  name        = "allow_web"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow ssh inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "ssh from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}

# resource "aws_instance" "web" {
#   # ami           = "ami-0261755bbcb8c4a84"   
#   ami           = "ami-0c65adc9a5c1b5d7c"   
#   instance_type = "t2.micro"
#   subnet_id     =  aws_subnet.public_subnets["public_subnet_1"].id
#   # vpc_security_group_ids = ["sg-0aad40876448a8090"]

#   tags = {
#     "Name" = "web resource"
#     "Terraform" = "true"
#   }
# }

resource "aws_s3_bucket" "my-new-S3-bucket" {
  bucket = "my-new-tf-test-bucket-${random_id.randomness.hex}"
  tags = {
    Name    = "My S3 Bucket"
    Purpose = "Intro to Resource Blocks Lab"
  }
}

resource "aws_s3_bucket_ownership_controls" "my_new_bucket_acl" {
  bucket = aws_s3_bucket.my-new-S3-bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "my-new-S3-bucket-acl" {
  bucket     = aws_s3_bucket.my-new-S3-bucket.id
  acl        = "private"
  depends_on = [aws_s3_bucket_ownership_controls.my_new_bucket_acl]
}

resource "aws_security_group" "ingress-443" {
  name = "web_server_inbound"

  description = "Allow inbound traffic on tcp/443"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Allow 443 from the Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "web_server_443_inbound"
    Purpose = "Intro to Resource Blocks Lab"
  }
}

resource "aws_security_group" "main" {
  name = "main-global"

  description = "AllowDoes nothing"
  vpc_id      = aws_vpc.vpc.id

  tags = {
    Name    = "main"
    Purpose = "Does nothing"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "random_id" "randomness" {
  byte_length = 16
}

resource "aws_subnet" "list_subnet" {
  for_each          = var.ip
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = each.value
  availability_zone = var.us-east-1-azs[0]
  tags = {
    Environment  = var.environment
    "CIDR block" = each.value
  }
}

# Static Values
# resource "aws_subnet" "variables-subnet" {
#   vpc_id                  = aws_vpc.vpc.id
#   cidr_block              = var.variables_sub_cidr
#   availability_zone       = var.variables_sub_az
#   map_public_ip_on_launch = var.variables_sub_auto_ip
#   tags = {
#     Name      = "sub-variables-${var.variables_sub_az}"
#     Terraform = "true"
#   }
# }

# New webserver for Taint test
# resource "aws_instance" "web_server2" {
#   ami                         = data.aws_ami.ubuntu.id
#   instance_type               = "t2.micro"
#   subnet_id                   = aws_subnet.public_subnets["public_subnet_1"].id
#   vpc_security_group_ids      = [aws_security_group.allow_ssh.id, aws_security_group.allow_web.id]
#   associate_public_ip_address = true
#   key_name                    = aws_key_pair.developer.key_name
#   connection {
#     user        = "ubuntu"
#     private_key = tls_private_key.generated.private_key_pem
#     host        = self.public_ip
#   }

#   # Leave the first part of the block unchanged and create our `local-exec` provisioner
#   provisioner "local-exec" {
#     command = "chmod 600 ${local_file.private_key_pem.filename}"
#   }
#   provisioner "remote-exec" {
#     inline = [
#       "sudo rm -rf /tmp",
#       "sudo git clone https://github.com/hashicorp/demo-terraform-101 /tmp",
#       "sudo sh /tmp/assets/setup-web.sh",
#     ]
#   }
#   tags = {
#     Name = "Web EC2 Server"
#   }
#   lifecycle {
#     ignore_changes = [security_groups]
#   }
# }

# resource "aws_instance" "aws_import" {
#   ami                                  = data.aws_ami.ubuntu.id
#   instance_type                        = "t2.micro"
#   tags                                 = {
#         "Name" = "import-test"
#     }
#     tags_all                             = {
#         "Name" = "import-test"
#     }
# }

# module "server" {
#   source    = "./modules/server"
#   ami       = data.aws_ami.ubuntu.id
#   subnet_id = aws_subnet.public_subnets["public_subnet_3"].id
#   security_groups = [
#     aws_security_group.allow_ssh.id,
#     aws_security_group.allow_web.id
#   ]
# }

module "server_subnet_1" {
  source    = "./modules/web_server"
  ami       = data.aws_ami.ubuntu.id
  subnet_id = aws_subnet.public_subnets["public_subnet_1"].id
  security_groups = [
    aws_security_group.allow_ssh.id,
    aws_security_group.allow_web.id,
    aws_security_group.main.id
  ]
  user        = "ubuntu"
  key_name    = aws_key_pair.developer.key_name
  private_key = tls_private_key.generated.private_key_pem
}

# module "autoscaling" {
#   source  = "terraform-aws-modules/autoscaling/aws"
#   version = "6.10.0"
#   # Autoscaling group
#   name = "myasg"
#   vpc_zone_identifier = [aws_subnet.private_subnets["private_subnet_1"].id,
#     aws_subnet.private_subnets["private_subnet_2"].id,
#     aws_subnet.private_subnets["private_subnet_3"].id
#   ]
#   min_size         = 0
#   max_size         = 1
#   desired_capacity = 1
#   # Launch template
#   # use_lt        = true
#   # create_lt     = true
#   image_id      = data.aws_ami.ubuntu.id
#   instance_type = "t3.micro"
#   tags = {
#     Name = "Web EC2 Server 2"
#   }
# }

# output "public_ip_server_subnet_1" {
#   value = module.server_subnet_1.public_ip
# }
# output "public_dns_server_subnet_1" {
#   value = module.server_subnet_1.public_dns
# }

# output "public_ip" {
#   value = module.server.public_ip
# }
# output "public_dns" {
#   value = module.server.public_dns
# }

output "web_server-ip" {
  value = aws_instance.web_server.public_ip
}

