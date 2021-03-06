#!/bin/bash

set -euo pipefail

# Creates interflo template repository to be used as parent project for other repositories in which interflo group should be enforced. Also creates sample account for student with username student123
# interflo have push and read access only to theirs set of branches under refs/heads/${username}/sandbox/*. Also anonymous reads are prohibited in order to not pass the  permissions and see other users results.
# Following arguments must be supplied to script:
# gerrit_authorized_url
# gerrit_username
# gerrit_user_email
# gerrit_template_repo_name

if [[ ! $# -eq 4 ]]; then
    echo "Please supply gerrit authorized url, gerrit_username, gerrit_user_email and gerrit_template_repo_name"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "jq not found, please install the command and rerun the script ${0}"
    exit 1
fi

gerrit_authorized_url="$1"
gerrit_username="$2"
gerrit_user_email="$3"
gerrit_template_repo_name="$4"
config_files_location="gerrit/interflo-template-projects-config"
student_username='student123'

# Create sample student account in gerrit with username and password student123
curl --header "Content-Type: application/json" \
    --request PUT \
    --fail \
    --silent \
    --show-error \
    --output /dev/null \
    --data '{"name":"'"${student_username}"'", "email": "'"${student_username}@example.com"'", "http_password":"'"${student_username}"'"}' \
    "${gerrit_authorized_url}/accounts/${student_username}"

# Create interflo template repository (base for other projects)
curl --header "Content-Type: application/json" \
    --request PUT \
    --fail \
    --silent \
    --show-error \
    --output /dev/null \
    --data '{"description":"Template repository configured with special Registered users access group", "permissions_only": true, "parent": "", "create_empty_commit":false, "owners": ["Administrators"]}' \
    "${gerrit_authorized_url}/projects/${gerrit_template_repo_name}"


# Clone interflo template repository to host system with commit-msg hook
rm -rf "$gerrit_template_repo_name"

git clone "${gerrit_authorized_url}/${gerrit_template_repo_name}" && cd "$gerrit_template_repo_name"
mkdir -p .git/hooks
commit_msg_hook=$(git rev-parse --git-dir)/hooks/commit-msg 
curl -sSLo "${commit_msg_hook}" "${gerrit_authorized_url}"/tools/hooks/commit-msg 
chmod +x "${commit_msg_hook}"

# Save gerrit user credentials in local git config
git config --local user.name "${gerrit_username}" 
git config --local user.email "${gerrit_user_email}"

# Move configs to repository
/bin/cp -a "../$config_files_location/." .

# We have to include all groups to which permissions we set in groups file, these are:
# global group: Registered users
# internal groups:  Administrators, Non-Interactive Users -> We have to paste in admin group uuid generated by gerrit

# Fetch Administrators uuid group
administrators_group_uuid=$(curl --header "Content-Type: application/json" \
    --request GET \
    "${gerrit_authorized_url}/groups/Administrators" \
    | sed '1d'  \
    | jq -r '.id' \
    )

# Fetch Non-Interactive Users uuid group
non_interactive_group_uuid=$(curl --header "Content-Type: application/json" \
    --request GET \
    "${gerrit_authorized_url}/groups/Non-Interactive%20Users" \
    | sed '1d'  \
    | jq -r '.id' \
    )

# Replace  uuid for  administrators and non_interactive group
sed -i "s/administrators_group_uuid/${administrators_group_uuid}/" groups
sed -i "s/non_interactive_group_uuid/${non_interactive_group_uuid}/" groups

# Push all changes to the repository
git commit -a -m "Configure access rights for Registered users"
git push origin HEAD:refs/meta/config

printf "Success,  base repo %s has been created\n" "$gerrit_template_repo_name"
