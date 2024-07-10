#!/usr/bin/env bash

source .env

if [ -z $REPO_ACCT ]; then
  echo "REPO_ACCT is not set, exiting..."
  exit 1
fi

if [ -z $REPO_ACCT_LABEL ]; then
  echo "REPO_ACCT_LABEL is not set, exiting..."
  exit 1
fi

if [[ $REPO_ACCT -ne $AWS_ACCOUNT_ID ]]; then
  echo "Current AWS Account (${AWS_ACCOUNT_ID} ${AWS_ACCOUNT_ALIAS}) is not the repository account (${REPO_ACCT} ${REPO_ACCT_LABEL}), exiting..."
  exit 1
fi

get_ecr_repos(){
  aws ecr describe-repositories \
    --query 'repositories[*].repositoryName' \
    --output text
}

echo "Getting latest image versions for all ECR repositories..."
echo
rm -f ${LATEST_IMAGES_FILE}

for repo in $(get_ecr_repos); do
  repo_path="$REPO_ACCT.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$repo"
  { 
    tag=$(aws ecr describe-images \
      --repository-name $repo \
      --query 'imageDetails[*].imageTags' \
      --output text | sort -V | tail -n 1)
    echo "${repo_path}:${tag}" | tee -a ${LATEST_IMAGES_FILE}
  } &
done

wait && echo -e "\nDone"
