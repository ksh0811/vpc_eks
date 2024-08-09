terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 5.0"
    }   
  }
}

# vpc define
resource "aws_vpc" "this" {
  cidr_block = "10.50.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "eks-vpc"
  }
}

# igw create
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "eks-vpc-igw"
  }
}
# igw attach  (vpc id를 잘 명시할 경우. 자동으로 attached)

# eip create for natgw
resource "aws_eip" "this" {
  lifecycle {
    create_before_destroy = true
  }
  tags = {
    Name = "eks-vpc-eip"
  }
}

# pub sub create
resource "aws_subnet" "pub_sub1" {
  vpc_id = aws_vpc.this.id
  cidr_block = "10.50.10.0/24"
  map_public_ip_on_launch = true
  enable_resource_name_dns_a_record_on_launch = true
  availability_zone = "ap-northeast-2a"
  tags = { 
    Name = "eks-vpc-pub-sub1"
    "kubernetes.io/cluster/pri-cluster" = "owned"
    "kubernetes.io/role/elb" = "1"
  }
  depends_on = [ aws_internet_gateway.this ]
}

resource "aws_subnet" "pub_sub2" {
  vpc_id = aws_vpc.this.id
  cidr_block = "10.50.11.0/24"
  map_public_ip_on_launch = true
  enable_resource_name_dns_a_record_on_launch = true
  availability_zone = "ap-northeast-2c"
  tags = { 
    Name = "eks-vpc-pub-sub2"
    "kubernetes.io/cluster/pri-cluster" = "owned"
    "kubernetes.io/role/elb" = "1"
  }
  depends_on = [ aws_internet_gateway.this ]
}

# natgw create
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.this.id
  subnet_id = aws_subnet.pub_sub1.id
  tags = {
    Name = "eks-vpc-natgw"
  }
  lifecycle {
    create_before_destroy = true
  }
}

# pri sub create
resource "aws_subnet" "pri_sub1" {
  vpc_id = aws_vpc.this.id
  cidr_block = "10.50.20.0/24"
  enable_resource_name_dns_a_record_on_launch = true
  availability_zone = "ap-northeast-2a"
  tags = { 
    Name = "eks-vpc-pri-sub1"
    "kubernetes.io/cluster/pri-cluster" = "owned"
    "kubernetes.io/role/internal-elb" = "1"
  }
  depends_on = [ aws_nat_gateway.this ]
}


resource "aws_subnet" "pri_sub2" {
  vpc_id = aws_vpc.this.id
  cidr_block = "10.50.21.0/24"
  enable_resource_name_dns_a_record_on_launch = true
  availability_zone = "ap-northeast-2c"
  tags = { 
    Name = "eks-vpc-pri-sub2"
    "kubernetes.io/cluster/pri-cluster" = "owned"
    "kubernetes.io/role/internal-elb" = "1"
  }
  depends_on = [ aws_nat_gateway.this ]
}

# routeing table for pub sub
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "10.50.0.0/16"
    gateway_id = "local"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "eks-vpc-pub-rt"
  }

}

# routeing table for pri sub
resource "aws_route_table" "pri_rt" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "10.50.0.0/16"
    gateway_id = "local"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "eks-vpc-pri-rt"
  }

}

# routeing table - sub attach
resource "aws_route_table_association" "pub1_rt_asso" {
  subnet_id = aws_subnet.pub_sub1.id
  route_table_id = aws_route_table.pub_rt.id
}
resource "aws_route_table_association" "pub2_rt_asso" {
  subnet_id = aws_subnet.pub_sub2.id
  route_table_id = aws_route_table.pub_rt.id
}
resource "aws_route_table_association" "pri1_rt_asso" {
  subnet_id = aws_subnet.pri_sub1.id
  route_table_id = aws_route_table.pri_rt.id
}
resource "aws_route_table_association" "pri2_rt_asso" {
  subnet_id = aws_subnet.pri_sub2.id
  route_table_id = aws_route_table.pri_rt.id
}

# sg create
resource "aws_security_group" "eks-vpc-pub-sg" {
  vpc_id = aws_vpc.this.id
  name = "eks-vpc-pub-sg"
  tags = {
    Name = "eks-vpc-pub-sg"
  }
}

# ingress & egress role define
resource "aws_security_group_rule" "eks-vpc-http-ingress" {
  type = "ingress"
  from_port = 80
  to_port = 80
  protocol = "TCP"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks-vpc-pub-sg.id
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_security_group_rule" "eks-vpc-ssh-ingress" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "TCP"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks-vpc-pub-sg.id
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "eks-vpc-egress" {
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = [ "0.0.0.0/0" ]
  security_group_id = aws_security_group.eks-vpc-pub-sg.id
  lifecycle {
    create_before_destroy = true
  }
}

