terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.63"
    }

    aws-dnssec-key-provider = {
      source  = "hashicorp/aws"
      version = "~> 3.63"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~>2.4"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~>2.7"
    }

    local = {
      source  = "hashicorp/local"
      version = "~>2.1"
    }

    null = {
      source = "hashicorp/null"
    }
    template = {
      source = "hashicorp/template"
    }
    time = {
      source = "hashicorp/time"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
  required_version = "~> 1.1.5"
}
