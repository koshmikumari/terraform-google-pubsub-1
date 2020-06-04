terraform {
  required_version = ">= 0.12.24" # see https://releases.hashicorp.com/terraform/
  experiments      = [variable_validation]
}

provider "google" {
  version = ">= 3.13.0" # see https://github.com/terraform-providers/terraform-provider-google/releases
}

locals {
  topic_name = format("%s-%s", var.topic_name, var.name_suffix)
  push_subscriptions = [
    for subscription in var.push_subscriptions :
    {
      name                       = format("%s-%s-push-%s", var.topic_name, subscription.name, var.name_suffix)
      push_endpoint              = subscription.push_endpoint
      auth_sa_email              = lookup(subscription, "auth_sa_email", null)
      auth_audience              = lookup(subscription, "auth_audience", null)
      ack_deadline_seconds       = lookup(subscription, "ack_deadline_seconds", var.default_ack_deadline_seconds)
      message_retention_duration = lookup(subscription, "message_retention_duration", var.default_message_retention_duration)
    }
  ]
  pull_subscriptions = [
    for subscription in var.pull_subscriptions :
    {
      name                       = format("%s-%s-pull-%s", var.topic_name, subscription.name, var.name_suffix)
      ack_deadline_seconds       = lookup(subscription, "ack_deadline_seconds", var.default_ack_deadline_seconds)
      message_retention_duration = lookup(subscription, "message_retention_duration", var.default_message_retention_duration)
    }
  ]
}

resource "google_project_service" "pubsub_api" {
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

resource "google_pubsub_topic" "topic" {
  name       = local.topic_name
  depends_on = [google_project_service.pubsub_api]
}

resource "google_pubsub_subscription" "push_subscriptions" {
  count                      = length(local.push_subscriptions)
  name                       = local.push_subscriptions[count.index].name
  topic                      = google_pubsub_topic.topic.name
  ack_deadline_seconds       = local.push_subscriptions[count.index]["ack_deadline_seconds"]
  message_retention_duration = local.push_subscriptions[count.index]["message_retention_duration"]
  push_config {
    push_endpoint = local.push_subscriptions[count.index]["push_endpoint"]
    dynamic "oidc_token" {
      # add this block only if 'auth_sa_email' is present for this subscription
      for_each = local.push_subscriptions[count.index]["auth_sa_email"] == null ? [] : [1]
      content {
        service_account_email = local.push_subscriptions[count.index]["auth_sa_email"]
        audience              = local.push_subscriptions[count.index]["auth_audience"]
      }
    }
  }
  depends_on = [google_project_service.pubsub_api]
}

resource "google_pubsub_subscription" "pull_subscriptions" {
  count                      = length(local.pull_subscriptions)
  name                       = local.pull_subscriptions[count.index].name
  topic                      = google_pubsub_topic.topic.name
  ack_deadline_seconds       = local.pull_subscriptions[count.index]["ack_deadline_seconds"]
  message_retention_duration = local.pull_subscriptions[count.index]["message_retention_duration"]
  depends_on                 = [google_project_service.pubsub_api]
}
