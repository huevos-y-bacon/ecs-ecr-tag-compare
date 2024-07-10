#!/usr/bin/env bash

source .env

BOLD=$(tput bold)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
RESET=$(tput sgr0)
GREY=$(tput setaf 8)

if [ ! -f "${LATEST_IMAGES_FILE}" ]; then
  echo "${RED}File ${LATEST_IMAGES_FILE} not found."
  echo
  echo "${RESET}Run the following command to create it:"
  echo "  ./get_ecr_latest_images.sh ${GREY}# run this in the repo account"
  exit 1
fi    

function process_service {
  echo "  - name: ${BOLD}${service_name}${RESET}"
  echo "    arn: ${service}${RESET}"
  # Describe the service to get the taskDefinition
  descr_svc=$(aws ecs describe-services --cluster "${cluster}" --services "${service}")
  task_definition=$(echo ${descr_svc} | jq -r '.services[0].taskDefinition')
  echo "    taskDefinition: ${task_definition}"

  # Describe the taskDefinition to get the container definitions
  descr_td=$(aws ecs describe-task-definition --task-definition "${task_definition}")
  container_definitions=$(echo ${descr_td} | jq -c '.taskDefinition.containerDefinitions[]')

  # Iterate over each container definition to get the image
  echo "      containers: ${container_name}${RESET}"
  echo "${container_definitions}" | while IFS= read -r container; do
    container_name=$(echo "${container}" | jq -r '.name')
    # echo $container | jq > tmp_container_$container_name.json
    echo "      - name: ${BOLD}${container_name}${RESET}"
    image=$(echo "${container}" | jq -r '.image')
    repo=$(echo "${image}" | cut -d':' -f1) # strip the image tag from the image
    echo "        repo: ${repo}${RESET}"
    repo_uri=$(echo "${image}" | cut -d'/' -f2-)
    image_tag=$(echo "${repo_uri}" | cut -d':' -f2)
    echo "        tag:"
    echo "          current: ${image_tag}${RESET}"

    if [ -f "${LATEST_IMAGES_FILE}" ]; then
      latest_tag=$(grep "${repo}" "${LATEST_IMAGES_FILE}" | cut -d':' -f2)
      if [ ${image_tag} != ${latest_tag} ]; then _col=${RED}; else _col=${GREEN}; fi
      echo "          ${_col}latest: ${latest_tag}${RESET}"
    fi    
  done
}

OUTPUT="${AWS_ACCOUNT_ALIAS}_ecs_services_images.txt"
echo "aws_account_id: ${AWS_ACCOUNT_ID}
aws_account_alias: ${AWS_ACCOUNT_ALIAS}" | tee ${OUTPUT}

# echo "Fetch all ECS clusters"
CLUSTERS=$(aws ecs list-clusters | jq -r '.clusterArns[]')
if [ -z "${CLUSTERS}" ]; then
  echo "No clusters found"
  exit 0
fi

for cluster in ${CLUSTERS}; do
  echo -e "cluster: ${cluster}" | tee -a ${OUTPUT}

  # echo "Fetch all services in the cluster"
  services=$(aws ecs list-services --cluster "${cluster}" | jq -r '.serviceArns[]')

  if [ -z "$services" ]; then
    echo "No services found in cluster ${cluster}"
    exit 1
  fi

  echo "services:" | tee -a ${OUTPUT}
  for service in $services; do
    service_name=$(echo "${service}" | cut -d'/' -f3)
    process_service > ${service_name}.output &
    continue
  done
  wait
  echo
  for f in *.output; do cat ${f} |tee -a ${OUTPUT}; done && rm -f ./*.output
done

wait # && echo -e "\nDone"
