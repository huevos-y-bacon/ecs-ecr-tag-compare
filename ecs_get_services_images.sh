#!/usr/bin/env bash

source .env

function col(){
  BOLD=$(tput bold)
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  RESET=$(tput sgr0)
  GREY=$(tput setaf 8)
}

unset BOLD RED GREEN RESET GREY
[[ -z $NOCOL ]] && col

if [ ! -f "${LATEST_IMAGES_FILE}" ]; then
  echo "${RED}File ${LATEST_IMAGES_FILE} not found."
  echo
  echo "${RESET}Run the following command to create it:"
  echo "  ./get_ecr_latest_images.sh ${GREY}# Run this in the repo account"
  exit 1
fi

function process_service {
  descr_svc=$(aws ecs describe-services --cluster "${cluster}" --services "${service}")
  task_definition=$(echo ${descr_svc} | jq -r '.services[0].taskDefinition')
  task_definition_name=$(echo "${task_definition}" | cut -d'/' -f2)
  descr_td=$(aws ecs describe-task-definition --task-definition "${task_definition}") # Describe the task definition
  container_definitions=$(echo ${descr_td} | jq -c '.taskDefinition.containerDefinitions[]')

  echo
  echo "  - name: ${BOLD}${service_name}${RESET}"
  echo "    arn: ${service}${RESET}"
  echo "    task_definition:"
  echo "      arn: ${task_definition}"
  echo "      containers:${RESET}"

  # Iterate over each container definition to get the image
  echo "${container_definitions}" | while IFS= read -r container; do
    container_name=$(echo "${container}" | jq -r '.name')
    image=$(echo "${container}" | jq -r '.image') # Get the image from the container definition
    repo=$(echo "${image}" | cut -d':' -f1) # Strip the image tag from the image
    repo_uri=$(echo "${image}" | cut -d'/' -f2-) # Get the repo URI from the image
    repo_account=$(echo "${repo}" | cut -d'.' -f1) # Get the repo account from the repo
    repo_name=$(echo "${repo_uri}" | cut -d'/' -f2-) # Get the repo name from the repo_uri
    repo_name=$(echo "${repo_name}" | cut -d':' -f1) # Strip the image tag from the repo_name
    image_tag=$(echo "${repo_uri}" | cut -d':' -f2) # Get the image tag from the repo_uri

    # echo "        containers: ${container_name}${RESET}"
    echo "        - name: ${BOLD}${container_name}${RESET}"
    echo "          repo: ${repo}${RESET}"
    echo "          tag:"
    echo "            current: ${image_tag}${RESET}"

    if [ -f "${LATEST_IMAGES_FILE}" ]; then
      latest_tag=$(grep "${repo}" "${LATEST_IMAGES_FILE}" | cut -d':' -f2)
      if [ ${image_tag} != ${latest_tag} ]; then _col=${RED}; else _col=${GREEN}; fi
      echo "            ${_col}latest: ${latest_tag}${RESET}"
    fi

    # Write CSV row
    echo "${AWS_ACCOUNT_ALIAS},${AWS_ACCOUNT_ID},${cluster_name},${service_name},${task_definition_name},${container_name},${repo_account},${repo_name},${image_tag},${latest_tag}" >> ${OUTPUT_CSV}
  done
}

OUTPUT="${AWS_ACCOUNT_ALIAS}_ecs_services_images.txt"
OUTPUT_CSV="${AWS_ACCOUNT_ALIAS}_ecs_services_images.csv"

CSV_HEADERS="aws_account_alias,aws_account_id,cluster,service,task_definition,container,repo_account,repo_name,tag_current,tag_latest"
echo "${CSV_HEADERS}" > ${OUTPUT_CSV}

echo -e "aws_account_id: ${AWS_ACCOUNT_ID}\naws_account_alias: ${AWS_ACCOUNT_ALIAS}\n" | tee ${OUTPUT}

CLUSTERS=$(aws ecs list-clusters | jq -r '.clusterArns[]')
if [ -z "${CLUSTERS}" ]; then
  echo "No clusters found"
  exit 0
fi

for cluster in ${CLUSTERS}; do
  echo -e "cluster: ${cluster}" | tee -a ${OUTPUT}

  cluster_name=$(echo "${cluster}" | cut -d'/' -f2) # Get the cluster name from the cluster ARN
  services=$(aws ecs list-services --cluster "${cluster}" | jq -r '.serviceArns[]')

  if [ -z "$services" ]; then
    echo "No services found in cluster ${cluster}"
    exit 1
  fi

  echo "services:" | tee -a ${OUTPUT}
  for service in $services; do
    service_name=$(echo "${service}" | cut -d'/' -f3) # Get the service name from the service ARN
    process_service > ${service_name}.output &
    continue
  done
  wait && echo
  for f in *.output; do cat ${f} | tee -a ${OUTPUT}; done && rm -f ./*.output
done

wait
printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' _ # print a line of underscores
echo -e "\n${GREEN}Output files:\n  yaml: ${OUTPUT}\n  csv:  ${OUTPUT_CSV}${RESET}"
