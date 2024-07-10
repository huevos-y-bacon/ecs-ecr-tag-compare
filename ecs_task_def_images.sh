#!/usr/bin/env bash
source .env

# Get all AWS ECS task definitions

get_task_defs(){
  echo "Getting all task definitions..."
  echo
  for td in $(aws ecs list-task-definitions --query "taskDefinitionArns" --output text); do
    # Strip the arn prefix
    output="$(echo $td | cut -d '/' -f 2).json"
    if [ -f $output ]; then
      echo "Skipping $td, already exists"
      continue
    fi
    echo "Getting task definition $td"
    aws ecs describe-task-definition --task-definition $td > $output &
  done

  wait && echo "Done getting task definitions"
}

get_task_defs

# example output
# {
#     "taskDefinition": {
#         "taskDefinitionArn": "arn:aws:ecs:eu-west-1:112233445566:task-definition/my-service-td:5",
#         "containerDefinitions": [
#             {
#                 "name": "acs",
#                 "image": "223344556677.dkr.ecr.eu-west-1.amazonaws.com/acme/my-project/prod/my-service:2.0.2",
#                 "cpu": 512,
#                 ...
#             },
#             {
#                 "name": "xray-daemon",
#                 "image": "223344556677.dkr.ecr.eu-west-1.amazonaws.com/acme/my-project/prod/x-ray-daemon:3.2.0",
#                 "cpu": 0,
#                 ...
#             }
#         ]
#     }
# }

echo
echo "Getting all image arns from all task definitions..."
echo

# shellcheck disable=2045,2035
for f in $(ls *.json); do
  jq -r '.taskDefinition.containerDefinitions[].image' $f
done | sort | uniq | tee ${AWS_ACCOUNT_ALIAS}_ecs_task_def_images.txt
