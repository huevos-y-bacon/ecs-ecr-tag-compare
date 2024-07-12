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
  echo "  - name: ${BOLD}${service_name}${RESET}"
  echo "    arn: ${service}${RESET}"

  # Describe the service to get the taskDefinition
  descr_svc=$(aws ecs describe-services --cluster "${cluster}" --services "${service}")
  task_definition=$(echo ${descr_svc} | jq -r '.services[0].taskDefinition')
  echo "    task_definition: ${task_definition}"

  # Build CSV row - task definition
  task_definition_name=$(echo "${task_definition}" | cut -d'/' -f2)
  csv_td="${csv_service},${task_definition_name}"

  # Describe the taskDefinition to get the container definitions
  descr_td=$(aws ecs describe-task-definition --task-definition "${task_definition}")
  container_definitions=$(echo ${descr_td} | jq -c '.taskDefinition.containerDefinitions[]')

  # Iterate over each container definition to get the image
  echo "      containers: ${container_name}${RESET}"
  echo "${container_definitions}" | while IFS= read -r container; do
    container_name=$(echo "${container}" | jq -r '.name')

    # Build CSV row - container
    csv_container="${csv_td},${container_name}"

    echo "      - name: ${BOLD}${container_name}${RESET}"
    image=$(echo "${container}" | jq -r '.image')

    # Strip the image tag from the image
    repo=$(echo "${image}" | cut -d':' -f1)
    echo "        repo: ${repo}${RESET}"
    repo_uri=$(echo "${image}" | cut -d'/' -f2-)

    # Build CSV row - repo_account
    repo_account=$(echo "${repo}" | cut -d'.' -f1)
    csv_repo_account="${csv_container},${repo_account}"

    # Build CSV row - repo_name
    repo_name=$(echo "${repo_uri}" | cut -d'/' -f2-)
    # Strip the image tag from the repo_name
    repo_name=$(echo "${repo_name}" | cut -d':' -f1)

    csv_repo_name="${csv_repo_account},${repo_name}"
    image_tag=$(echo "${repo_uri}" | cut -d':' -f2)

    # Build CSV row - current
    csv_tag="${csv_repo_name},${image_tag}"

    echo "        tag:"
    echo "          current: ${image_tag}${RESET}"

    if [ -f "${LATEST_IMAGES_FILE}" ]; then
      latest_tag=$(grep "${repo}" "${LATEST_IMAGES_FILE}" | cut -d':' -f2)

      # Build CSV row - latest
      csv_latest="${csv_tag},${latest_tag}"

      if [ ${image_tag} != ${latest_tag} ]; then _col=${RED}; else _col=${GREEN}; fi
      echo "          ${_col}latest: ${latest_tag}${RESET}"
    fi

    # Write CSV row
    echo $csv_latest >> ${OUTPUT_CSV}
  done
}

OUTPUT="${AWS_ACCOUNT_ALIAS}_ecs_services_images.txt"
OUTPUT_CSV="${AWS_ACCOUNT_ALIAS}_ecs_services_images.csv"

csv_headers="aws_account_alias,aws_account_id,cluster,service,task_definition,container,repo_account,repo_name,tag_current,tag_latest"
echo $csv_headers > ${OUTPUT_CSV}
csv_prefix="${AWS_ACCOUNT_ALIAS},${AWS_ACCOUNT_ID}"

echo -e "aws_account_id: ${AWS_ACCOUNT_ID}\naws_account_alias: ${AWS_ACCOUNT_ALIAS}\n" | tee ${OUTPUT}

# Fetch all ECS clusters
CLUSTERS=$(aws ecs list-clusters | jq -r '.clusterArns[]')
if [ -z "${CLUSTERS}" ]; then
  echo "No clusters found"
  exit 0
fi

for cluster in ${CLUSTERS}; do
  echo -e "cluster: ${cluster}" | tee -a ${OUTPUT}

  # Build CSV row - cluster
  cluster_name=$(echo "${cluster}" | cut -d'/' -f2)
  csv_cluster="${csv_prefix},${cluster_name}"

  # Fetch all services in the cluster
  services=$(aws ecs list-services --cluster "${cluster}" | jq -r '.serviceArns[]')

  if [ -z "$services" ]; then
    echo "No services found in cluster ${cluster}"
    exit 1
  fi

  echo "services:" | tee -a ${OUTPUT}
  for service in $services; do
    service_name=$(echo "${service}" | cut -d'/' -f3)

    # Build CSV row - service
    csv_service="${csv_cluster},${service_name}"

    process_service > ${service_name}.output &
    continue
  done
  wait
  echo
  for f in *.output; do cat ${f} | tee -a ${OUTPUT}; done && rm -f ./*.output
done

wait
printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' _ # print a line of underscores
echo -e "\n${GREEN}Output files:\n  yaml: ${OUTPUT}\n  csv:  ${OUTPUT_CSV}${RESET}"
