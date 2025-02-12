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
        Action   = ["sts:AssumeRole"]
        Effect   = "Allow"
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
        Effect   = "Allow"
        Resource = "arn:aws:iam::*:user/$${aws:username}"
      },
    ]
  })
}
