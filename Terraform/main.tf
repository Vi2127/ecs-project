# main.tf

provider "aws" {
  region = var.region
}

#--------------------------------IAM---------------------------------------------------
# IAM role for ECS task execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"
  
  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "ecs-tasks.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }
    EOF
 }

# IAM policy for ECS task execution and CloudWatch Logs access
resource "aws_iam_policy" "ecs_task_execution_policy" {
  name        = "ecs-task-execution-policy"
  description = "Policy for ECS task execution and CloudWatch Logs access"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
          {
              "Effect": "Allow",
              "Action": [
                  "ecs:*",
                  "cloudwatch:*",
                  "logs:*"
              ],
              "Resource": "*"
          }
      ]
  } 
  EOF
}

# Attach the policy to the IAM role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_execution_policy.arn
  depends_on = [aws_iam_role.ecs_task_execution_role, aws_iam_policy.ecs_task_execution_policy]
}

#-------------------------------Network--------------------------------------------------
# Creating VPC for ecs
resource "aws_vpc" "jenkins_vpc" {
  cidr_block = var.vpc_cidr_block  # Adjust CIDR block as per your requirements
  enable_dns_support = true  #gives you an internal domain name
  enable_dns_hostnames = true   #gives you an internal host name
}

# Creating subnet under above vpc
resource "aws_subnet" "jenkins_subnet" {
  vpc_id            = aws_vpc.jenkins_vpc.id
  cidr_block        = var.subnet_cidr_block  # Adjust CIDR block as per your subnet requirements
  availability_zone = "us-east-1a"      # Specify the availability zone where you want the subnet to be created
  map_public_ip_on_launch = true
  
  depends_on = [aws_vpc.jenkins_vpc]
}
#Creating IGW
resource "aws_internet_gateway" "jenkins_igw" {
    vpc_id = aws_vpc.jenkins_vpc.id
}
#custum route table
resource "aws_route_table" "jenkins_public_crt" {
    vpc_id = aws_vpc.jenkins_vpc.id
    
    route {
        //associated subnet can reach everywhere
        cidr_block = "0.0.0.0/0" 
        //CRT uses this IGW to reach internet
        gateway_id =  aws_internet_gateway.jenkins_igw.id
    }
}
resource "aws_route_table_association" "jenkins-crta-public-subnet-1"{
    subnet_id = aws_subnet.jenkins_subnet.id
    route_table_id = aws_route_table.jenkins_public_crt.id
}


# Creating security group and rules for ecs
resource "aws_security_group" "jenkins_security_group" {
  vpc_id = aws_vpc.jenkins_vpc.id
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  depends_on = [aws_vpc.jenkins_vpc]
}

# Creating security_groups rules
resource "aws_vpc_security_group_ingress_rule" "allow_custum_tcp" {
  security_group_id = aws_security_group.jenkins_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
  depends_on = [aws_security_group.jenkins_security_group]
}

resource "aws_vpc_security_group_ingress_rule" "allow_custum_http" {
  security_group_id = aws_security_group.jenkins_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
  depends_on = [aws_security_group.jenkins_security_group]
}

resource "aws_vpc_security_group_ingress_rule" "allow_custum_https" {
  security_group_id = aws_security_group.jenkins_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
  depends_on = [aws_security_group.jenkins_security_group]
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh" {
  security_group_id = aws_security_group.jenkins_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
  depends_on = [aws_security_group.jenkins_security_group]
}
/*
resource "aws_vpc_security_group_ingress_rule" "allow_all" {
  security_group_id = aws_security_group.jenkins_security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 0
  ip_protocol       = "-1"
  to_port           = 0
  depends_on = [aws_security_group.jenkins_security_group]
}
*/
#------------------------------ECS & Logs---------------------------------------------------
# Creating log group for storing ecs log
resource "aws_cloudwatch_log_group" "jenkins_log" {
  name = "ecs/jenkins"
  depends_on = [aws_security_group.jenkins_security_group, aws_subnet.jenkins_subnet, aws_vpc.jenkins_vpc]
}

# Creating ecs cluster
resource "aws_ecs_cluster" "jenkins_cluster" {
  name = "jenkins-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Creating task_definition 
resource "aws_ecs_task_definition" "jenkins_task" {
  family                   = "jenkins-task"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = jsonencode([
                                {
                                  "name": "jenkins_image",
                                  "image": "public.ecr.aws/r4d2h1u3/jenkins:latest",
                                  "memory": 1024,
                                  "cpu": 512,
                                  "essential": true,
                                  "portMappings": [
                                    {
                                      "containerPort": 8080,
                                      "hostPort": 8080
                                    }
                                  ],
                                  "mountPoints": [
                                    {
                                      "sourceVolume": "jenkins-data", // Volume name here
                                      "containerPath": "/var/jenkins_home"
                                    }
                                  ],
                                  "logConfiguration": {
                                    "logDriver": "awslogs",
                                    "options": {
                                      "awslogs-group": "ecs/jenkins",
                                      "awslogs-region": "us-east-1",
                                      "awslogs-stream-prefix": "ecs"
                                    }
                                  }
                                }
                              ]
                                )
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"
  volume {
    name      = "jenkins-data"
  }
  depends_on = [aws_iam_role.ecs_task_execution_role, aws_iam_policy.ecs_task_execution_policy, aws_cloudwatch_log_group.jenkins_log]
}

resource "aws_ecs_service" "jenkins_service" {
  name            = "jenkins-service"
  cluster         = aws_ecs_cluster.jenkins_cluster.id
  task_definition = aws_ecs_task_definition.jenkins_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  #enable_execute_command = true                                 #added this line
  network_configuration {
    subnets         = [aws_subnet.jenkins_subnet.id]
    security_groups = [aws_security_group.jenkins_security_group.id]
    #subnets         = ["subnet-d55812b3"]
    #security_groups = ["sg-fa999be1"]
    assign_public_ip = true
  }
  enable_execute_command = true
  depends_on = [aws_ecs_task_definition.jenkins_task]
}

