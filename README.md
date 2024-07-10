# Compare image tags of running ECS containers to ECR images

Outputs yaml-like text, with ansi color coding.

1. Prepare `.env` (make copy of `example.env`)
2. In the REPO account, run:
    - `./get_ecr_latest_images.sh`
3. In each ECS account, run:
    - `./ecs_get_services_images.sh`
