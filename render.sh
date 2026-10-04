#!/usr/bin/env bash
# Fills the {{ PLACEHOLDERS }} in TEMPLATE.md with GitHub stats and writes README.md.
set -euo pipefail

login="${LOGIN:-angus-forrest-uk}"

read -r created issues pull_requests contributed_to < <(gh api graphql -f login="$login" -f query='
  query($login: String!) {
    user(login: $login) {
      createdAt
      issues { totalCount }
      pullRequests { totalCount }
      repositoriesContributedTo { totalCount }
    }
  }' --jq '.data.user | [.createdAt, .issues.totalCount, .pullRequests.totalCount, .repositoriesContributedTo.totalCount] | @tsv')

age=$(( ($(date -u +%s) - $(date -u -d "$created" +%s)) / 31557600 ))

# contributionsCollection spans at most a year, so ask for one per calendar year.
years=""
for year in $(seq "${created:0:4}" "$(date -u +%Y)"); do
  years+="y$year: contributionsCollection(from: \"$year-01-01T00:00:00Z\", to: \"$year-12-31T23:59:59Z\") { totalCommitContributions } "
done
commits=$(gh api graphql -f login="$login" -f query="
  query(\$login: String!) { user(login: \$login) { $years } }" \
  --jq '[.data.user[].totalCommitContributions] | add')

sed \
  -e "s/{{ ACCOUNT_AGE }}/$age/" \
  -e "s/{{ COMMITS }}/$commits/" \
  -e "s/{{ ISSUES }}/$issues/" \
  -e "s/{{ PULL_REQUESTS }}/$pull_requests/" \
  -e "s/{{ REPOSITORIES_CONTRIBUTED_TO }}/$contributed_to/" \
  TEMPLATE.md > README.md
