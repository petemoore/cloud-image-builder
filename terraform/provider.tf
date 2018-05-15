provider "aws" {
    version = "~> 1.13"
    region = "${var.region}"
    profile = "${var.profile}"
}

