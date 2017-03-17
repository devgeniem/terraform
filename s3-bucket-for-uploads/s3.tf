variable "aws_bucket_name" {}

provider "aws" {
  alias  = "west"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "central"
  region = "eu-central-1"
}

resource "aws_iam_role" "replication" {
  name               = "${var.aws_bucket_name}-role-replication"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
}

resource "aws_iam_policy" "replication" {
    name = "${var.aws_bucket_name}-replication-policy"
    policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.uploads.arn}"
      ]
    },
    {
      "Action": [
        "s3:GetObjectVersion",
        "s3:GetObjectVersionAcl"
      ],
      "Effect": "Allow",
      "Resource": [
        "${aws_s3_bucket.uploads.arn}/*"
      ]
    },
    {
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.destination.arn}/*"
    }
  ]
}
POLICY
}

resource "aws_iam_policy_attachment" "replication" {
    name = "${var.aws_bucket_name}-attachment-replication"
    roles = ["${aws_iam_role.replication.name}"]
    policy_arn = "${aws_iam_policy.replication.arn}"
}

resource "aws_s3_bucket" "destination" {
    provider = "aws.west"
    bucket   = "${var.aws_bucket_name}-replication-1"
    region   = "eu-west-1"
    acl      = "public-read"

    versioning {
        enabled = true
    }

    lifecycle_rule {
        prefix = ""
        enabled = true

        noncurrent_version_expiration {
            days = 15
        }
    }
}

resource "aws_s3_bucket" "uploads" {
    provider = "aws.central"
    bucket   = "${var.aws_bucket_name}"
    acl      = "public-read"
    region   = "eu-central-1"

    versioning {
        enabled = true
    }

    lifecycle_rule {
        prefix = ""
        enabled = true

        noncurrent_version_expiration {
            days = 15
        }
    }

    replication_configuration {
        role = "${aws_iam_role.replication.arn}"
        rules {
            id     = "${var.aws_bucket_name}-replication"
            prefix = ""
            status = "Enabled"

            destination {
                bucket        = "${aws_s3_bucket.destination.arn}"
                storage_class = "STANDARD"
            }
        }
    }
}

resource "aws_iam_user" "uploads_user" {
    name = "${var.aws_bucket_name}-user"
}

resource "aws_iam_access_key" "uploads_user" {
    user = "${aws_iam_user.uploads_user.name}"
}

resource "aws_iam_user_policy" "wp_uploads_policy" {
    name = "WordPress-S3-Uploads"
    user = "${aws_iam_user.uploads_user.name}"

    # S3 policy from humanmade/s3-uploads for WordPress uploads
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Stmt1392016154000",
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetBucketAcl",
        "s3:GetBucketLocation",
        "s3:GetBucketPolicy",
        "s3:GetObject",
        "s3:GetObjectAcl",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:ListMultipartUploadParts",
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": [
        "arn:aws:s3:::${aws_s3_bucket.uploads.bucket}/*"
      ]
    },
    {
      "Sid": "AllowRootAndHomeListingOfBucket",
      "Action": ["s3:ListBucket"],
      "Effect": "Allow",
      "Resource": ["arn:aws:s3:::${aws_s3_bucket.uploads.bucket}"],
      "Condition":{"StringLike":{"s3:prefix":["*"]}}
    }
  ]
}
EOF
}

# These output the created access keys and bucket name
output "s3-bucket-name-main" {
    value = "${var.aws_bucket_name}"
}

output "s3-user-access-key" {
    value = "${aws_iam_access_key.uploads_user.id}"
}

output "s3-user-secret-key" {
    value = "${aws_iam_access_key.uploads_user.secret}"
}