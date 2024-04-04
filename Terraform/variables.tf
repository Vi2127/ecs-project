variable "region" {
    description = "This is a variable of type string"
    type        = string
    default     = "us-east-1"
}

variable "vpc_cidr_block" {
    description = "This is a variable of type string"
    type        = string
    default     = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
    description = "This is a variable of type string"
    type        = string
    default     = "10.0.1.0/24"
}