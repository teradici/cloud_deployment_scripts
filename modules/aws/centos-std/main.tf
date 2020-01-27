/*
 * Copyright (c) 2020 Teradici Corporation
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

locals {
  prefix = var.prefix != "" ? "${var.prefix}-" : ""

  # Windows computer names must be <= 15 characters, minus 4 chars for "-xyz"
  # where xyz is number of instances (0-999)
  host_name = substr("${local.prefix}${var.name}", 0, 11)

  startup_script = "centos-std-startup.sh"
}

resource "aws_s3_bucket_object" "centos-std-startup-script" {
  count = tonumber(var.instance_count) == 0 ? 0 : 1

  key     = local.startup_script
  bucket  = var.bucket_name
  content = templatefile(
    "${path.module}/${local.startup_script}.tmpl",
    {
      pcoip_registration_code  = var.pcoip_registration_code,
      domain_controller_ip     = var.domain_controller_ip,
      domain_name              = var.domain_name,
      service_account_username = var.service_account_username,
      service_account_password = var.service_account_password,
    }
  )
}

data "template_file" "user-data" {
  template = file("${path.module}/user-data.sh.tmpl")

  vars = {
    bucket_name = var.bucket_name,
    file_name   = local.startup_script,
  }
}

# Need to do this to look up AMI ID, which is different for each region
data "aws_ami" "ami" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_name]
  }
}

data "aws_iam_policy_document" "instance-assume-role-policy-doc" {
  statement {
    actions = [ "sts:AssumeRole" ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "centos-std-role" {
  count = tonumber(var.instance_count) == 0 ? 0 : 1

  name               = "centos_std_role"
  assume_role_policy = data.aws_iam_policy_document.instance-assume-role-policy-doc.json
}

data "aws_iam_policy_document" "centos-std-policy-doc" {
  statement {
    actions   = ["ec2:DescribeTags"]
    resources = ["*"]
    effect    = "Allow"
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.bucket_name}/${local.startup_script}"]
    effect    = "Allow"
  }
}

resource "aws_iam_role_policy" "centos-std-role-policy" {
  count = tonumber(var.instance_count) == 0 ? 0 : 1

  name = "centos_std_role_policy"
  role = aws_iam_role.centos-std-role[0].id
  policy = data.aws_iam_policy_document.centos-std-policy-doc.json
}

resource "aws_iam_instance_profile" "centos-std-instance-profile" {
  count = tonumber(var.instance_count) == 0 ? 0 : 1

  name = "centos_std_instance_profile"
  role = aws_iam_role.centos-std-role[0].name
}

resource "aws_instance" "centos-std" {
  count = var.instance_count

  ami           = data.aws_ami.ami.id
  instance_type = var.instance_type

  root_block_device {
    volume_type = "gp2"
    volume_size = var.disk_size_gb
  }

  subnet_id                   = var.subnet
  associate_public_ip_address = var.enable_public_ip

  vpc_security_group_ids = var.security_group_ids

  key_name = var.admin_ssh_key_name

  iam_instance_profile = aws_iam_instance_profile.centos-std-instance-profile[0].name

  user_data = data.template_file.user-data.rendered

  tags = {
    Name = "${local.host_name}-${count.index}"
  }
}
