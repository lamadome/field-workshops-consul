module "acl_controller" {
  source  = "hashicorp/consul-ecs/aws//modules/acl-controller"
  version = "0.2.0"

  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.log_group.name
      awslogs-region        = var.vpc_region
      awslogs-stream-prefix = "consul-acl-controller"
    }
  }
  consul_bootstrap_token_secret_arn = aws_secretsmanager_secret.bootstrap_token.arn
  consul_server_http_addr           = data.terraform_remote_state.hcp.outputs.hcp_consul_public_endpoint_url
  ecs_cluster_arn                   = aws_ecs_cluster.this.arn
  region                            = var.vpc_region
  subnets                           = var.private_subnets_ids
  name_prefix                       = var.name
}

module "example_client_app" {
#  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
  source  = "git::https://github.com/hashicorp/terraform-aws-consul-ecs.git//modules/mesh-task?ref=main"

#  version = "0.2.0"
  consul_ecs_image  = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:latest"

  family            = "${var.name}-example-client-app"
  port              = "9090"
  log_configuration = local.example_client_app_log_config
  container_definitions = [{
    name             = "example-client-app"
    image            = "ghcr.io/lkysow/fake-service:v0.21.0"
    essential        = true
    logConfiguration = local.example_client_app_log_config
    environment = [
      {
        name  = "NAME"
        value = "${var.name}-example-client-app"
      },
      {
        name  = "UPSTREAM_URIS"
        value = "http://localhost:1234"
      }
    ]
    portMappings = [
      {
        containerPort = 9090
        hostPort      = 9090
        protocol      = "tcp"
      }
    ]
    cpu               = 1024
    memory            = 2048
    mountPoints = []
    volumesFrom = []
  }]
  upstreams = [
    {
#      destination_name = "${var.name}-example-server-app"
#      local_bind_port  = 1234
      destinationName = "${var.name}-example-server-app"
      localBindPort  = 1234

    }
  ]
  // Strip away the https prefix from the Consul network address
  retry_join                     = [substr(data.terraform_remote_state.hcp.outputs.hcp_consul_private_endpoint_url, 8, -1)]
  tls                            = true
  consul_server_ca_cert_arn      = aws_secretsmanager_secret.consul_ca_cert.arn
  gossip_key_secret_arn          = aws_secretsmanager_secret.gossip_key.arn
  acls                           = true
  consul_client_token_secret_arn = module.acl_controller.client_token_secret_arn
  acl_secret_name_prefix         = var.name
  consul_datacenter              = data.terraform_remote_state.hcp.outputs.consul_datacenter

  depends_on = [module.acl_controller, module.product-api]
}

module "product-api" {
  source  = "hashicorp/consul-ecs/aws//modules/mesh-task"
#  source  = "git::https://github.com/hashicorp/terraform-aws-consul-ecs.git//modules/mesh-task?ref=main"
  version = "0.3.0"
  consul_ecs_image  = "docker.mirror.hashicorp.services/hashicorpdev/consul-ecs:latest"

  family            = "${var.name}-product-api"
  cpu               = 1024
  memory            = 2048
  port              = "9090"
  log_configuration = local.product-api_log_config
  container_definitions = [{
    name             = "product-api"
    image            = "hashicorpdemoapp/product-api:v0.0.19"
    essential        = true
    logConfiguration = local.product-api_log_config
    environment = [
      {
        name  = "NAME"
        value = "${var.name}-product-api"
      }
    ]
  }]
  // Strip away the https prefix from the Consul network address
  retry_join                     = [substr(data.terraform_remote_state.hcp.outputs.hcp_consul_private_endpoint_url, 8, -1)]
  tls                            = true
  consul_server_ca_cert_arn      = aws_secretsmanager_secret.consul_ca_cert.arn
  gossip_key_secret_arn          = aws_secretsmanager_secret.gossip_key.arn
  acls                           = true
  consul_client_token_secret_arn = module.acl_controller.client_token_secret_arn
  acl_secret_name_prefix         = var.name
  consul_datacenter              = data.terraform_remote_state.hcp.outputs.consul_datacenter

  depends_on = [module.acl_controller]
}