variable "region" {
    description = "The region where to create resources."
    default = "eu-central-1"
}
variable "bucket" {
    description = "The bucket where to store a partner files."
    default = "partner-account-files"
}
variable "queue" {
    description = "The bucket where to store partner files."
    default = "partner-queue.fifo"
}