
resource "aws_s3_bucket" "relops_image_builder" {
    bucket = "relops-image-builder"
    acl = "private"
}

data "aws_iam_policy_document" "ec2_assume_role" {
    statement {
        actions = ["sts:AssumeRole"]
        effect = "Allow"
    principals {
        type = "Service"
        identifiers = ["ec2.amazonaws.com"]
        }
    }
}

resource "aws_iam_role" "image_builder_assume_role" {
    name = "image_builder_assume_role"
    assume_role_policy = "${data.aws_iam_policy_document.ec2_assume_role.json}"
}

data "aws_iam_policy_document" "s3_image_builder_access_policy" {
    statement = {
        sid = "AllowEC2ToReadKeyBucket"
        effect = "Allow"
        actions = [
            "s3:ListBucket",
        ]
        principals {
            type = "AWS"
            identifiers = [
                "${aws_iam_role.image_builder_assume_role.arn}",
            ]
        }
        resources = ["${aws_s3_bucket.relops_image_builder.arn}"]
    }
    statement = {
        sid = "AllowEC2ToReadKeyBucketObjects"
        effect = "Allow"
        actions = [
            "s3:Get*",
            "s3:List*",
        ]
        principals {
            type = "AWS"
            identifiers = [
                "${aws_iam_role.image_builder_assume_role.arn}",
            ]
        }
        resources = ["${aws_s3_bucket.relops_image_builder.arn}/*"]
    }
}

resource "aws_s3_bucket_policy" "image_builder_bucket_policy" {
    bucket = "${aws_s3_bucket.relops_image_builder.id}"
    policy = "${data.aws_iam_policy_document.s3_image_builder_access_policy.json}"
}

resource "aws_s3_bucket_object" "iso_prefix" {
  bucket = "relops-image-builder"
  key    = "ISOs/README"
  content = "Windows ISOs go here"
}

resource "aws_s3_bucket_object" "vhd_prefix" {
  bucket = "relops-image-builder"
  key    = "VHDs/README"
  content = "Windows VHDs go here"
}

