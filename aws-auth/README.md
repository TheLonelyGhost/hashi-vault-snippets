# AWS auth, served by IAM roles

Server-side:

```terraform
resource "aws_iam_role" "vault_server" {
  name_prefix = "VaultServer-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "cross_account" {
  name = "AwsAuth"
  role = aws_iam_role.vault_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole"]
        Effect = "Allow"
        Resource = "arn:aws:iam::*:role/VaultAuth"
      },
    ]
  })
}

resource "aws_iam_role_policy" "manage_self" {
  name = "ManageSelf"
  role = aws_iam_role.vault_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "iam:CreateAccessKey",
          "iam:DeleteAccessKey",
          "iam:GetAccessKeyLastUsed",
          "iam:GetUser",
          "iam:ListAccessKeys",
          "iam:UpdateAccessKey",
        ]
        Effect = "Allow"
        Resource = "arn:aws:iam::*:user/$${aws:username}"
      },
    ]
  })
}

```

Target account

```terraform

locals {
  vault_aws_account_nums = ["000000000", "000000001"]
  vault_fqdn = "vault.example.com"
}

resource "aws_iam_role" "vault_auth" {
  name = "VaultAuth"
  path = "/"
  description = <<-EOF
  Supports HashiCorp Vault in authenticating AWS identities
  (i.e., IAM Roles) cross-account
  EOF

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole"]
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Condition = {
          ArnLike = {
            "aws:PrincipalArn" = tolist([
              for acct in local.vault_aws_account_nums:
              "arn:aws:iam::${acct}:role/VaultServer-*"
            ])
          }
          # OPTIONAL SECURITY:
          # StringEquals = {
          #   "sts:ExternalId" = [local.vault_fqdn]
          # }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "vault_auth_ec2_verify" {
  name = "Ec2Verify"
  role = aws_iam_role.vault_auth.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeInstances",
          "iam:GetInstanceProfile",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "vault_auth_role_verify" {
  name = "IamRoleVerify"
  role = aws_iam_role.vault_auth.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "iam:GetRole",
          "iam:GetUser",
        ]
        Effect = "Allow"
        Resource = "*"
      },
    ]
  })
}
```

Vault configuration

```terraform
locals {
  target_aws_account_nums = []
  vault_fqdn = "vault.example.com"
}

resource "vault_auth_backend" "aws" {
  type = "aws"
}

resource "vault_aws_auth_backend_client" "client" {
  backend = vault_auth_backend.aws.path

  use_sts_region_from_client = true
}

resource "vault_aws_auth_backend_config_identity" "identity_config" {
  backend = vault_auth_backend.aws.path

  iam_alias = "role_id"  # GUID of the vault auth role, generated on role creation
  iam_metadata = [
    "canonical_arn",
    "account_id",
    "inferred_aws_region",
  ]
}

resource "vault_aws_auth_backend_sts_role" "sts" {
  for_each = toset(local.target_aws_account_nums)

  backend     = vault_auth_backend.aws.path
  account_id  = each.value
  sts_role    = "arn:aws:iam::${each.value}:role/VaultAuth"
  external_id = local.vault_fqdn
}
```

I prefer to manage STS role mappings in a more ad-hoc manner. Since the configuration for each account is low-churn, few parameters, and easily templated for each account, a python script does that.
