locals {
  vault_aws_account_nums = var.account_numbers
  vault_fqdn             = var.vault_fqdn
}

resource "aws_iam_role" "vault_auth" {
  name        = "VaultAuth"
  path        = "/"
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
              for acct in local.vault_aws_account_nums :
              "arn:aws:iam::${acct}:role/VaultServer-*"
            ])
          }
          StringEquals = {
            "sts:ExternalId" = [local.vault_fqdn]
          }
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
        Effect   = "Allow"
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
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}
