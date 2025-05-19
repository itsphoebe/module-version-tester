#!/bin/bash

# NOTE: THIS SCRIPT IS CURRENTLY NOT BEING CALLED BY JENKINS. JUST EXAMPLE ALTERNATIVE METHOD TO GET PROVIDER VERSIONS

# Gets highest minor releases for AWS provider via release tags from their git repo
# NOTE: Currently only works for the AWS provider! 

owner="hashicorp"
repo="terraform-provider-aws"
page=1
releases=()

while : ; do
  response=$(curl -s "https://api.github.com/repos/$owner/$repo/releases?page=$page&per_page=100")
  if [[ $(echo "$response" | jq '. | length') -eq 0 ]]; then
    break
  fi
  tags=$(echo "$response" | jq -r '.[].tag_name')
  releases+=($tags)
  ((page++))
done

sorted_releases=$(printf "%s\n" "${releases[@]}" | sort -Vr)
highest_minor_releases=()
prev_minor=""

for release in $sorted_releases; do
  minor=$(echo $release | awk -F. '{print $1"."$2}')
  if [[ $minor != $prev_minor ]]; then
    highest_minor_releases+=($release)
    prev_minor=$minor
  fi
done

# Output the array in reverse order
for ((i=${#highest_minor_releases[@]}-1; i>=0; i--)); do
  echo "${highest_minor_releases[i]:1}" # remove the "v" prefix
done