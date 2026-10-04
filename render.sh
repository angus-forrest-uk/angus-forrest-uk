#!/usr/bin/env bash
# Fills the {{ PLACEHOLDERS }} in TEMPLATE.md with GitHub stats and writes README.md.
set -euo pipefail

login="${LOGIN:-angus-forrest-uk}"

read -r created issues pull_requests contributed_to repositories stars < <(gh api graphql -f login="$login" -f query='
  query($login: String!) {
    user(login: $login) {
      createdAt
      issues { totalCount }
      pullRequests { totalCount }
      repositoriesContributedTo { totalCount }
      repositories(first: 100, ownerAffiliations: OWNER, isFork: false) {
        totalCount
        nodes { stargazerCount }
      }
    }
  }' --jq '.data.user | [.createdAt, .issues.totalCount, .pullRequests.totalCount, .repositoriesContributedTo.totalCount,
    .repositories.totalCount, ([.repositories.nodes[].stargazerCount] | add)] | @tsv')

age=$(( ($(date -u +%s) - $(date -u -d "$created" +%s)) / 31557600 ))

# contributionsCollection spans at most a year, so ask for one per calendar year.
# Private contributions are only reported as a single count, so they are added to the commits.
years=""
for year in $(seq "${created:0:4}" "$(date -u +%Y)"); do
  years+="y$year: contributionsCollection(from: \"$year-01-01T00:00:00Z\", to: \"$year-12-31T23:59:59Z\") {
    totalCommitContributions
    restrictedContributionsCount
    contributionCalendar { weeks { contributionDays { date contributionCount } } }
  } "
done
# The streak counts back from the latest day with a contribution, allowing for today
# being empty so far. The calendar is in the committer's timezone, which can be a day
# ahead of UTC, so keep one day past the UTC date and allow two empty days at the end.
read -r commits streak < <(gh api graphql -f login="$login" -f query="
  query(\$login: String!) { user(login: \$login) { $years } }" \
  --jq '(now + 86400 | strftime("%Y-%m-%d")) as $last
    | [.data.user[]] as $years
    | [$years[].contributionCalendar.weeks[].contributionDays[] | select(.date <= $last)] | sort_by(.date)
    | (if .[-1].contributionCount == 0 then .[:-1] else . end)
    | (if .[-1].contributionCount == 0 then .[:-1] else . end) | reverse
    | [([$years[] | .totalCommitContributions + .restrictedContributionsCount] | add), ((map(.contributionCount == 0) | index(true)) // length)] | @tsv')

sed \
  -e "s/{{ ACCOUNT_AGE }}/$age/" \
  -e "s/{{ COMMITS }}/$commits/" \
  -e "s/{{ ISSUES }}/$issues/" \
  -e "s/{{ PULL_REQUESTS }}/$pull_requests/" \
  -e "s/{{ STARS }}/$stars/" \
  -e "s/{{ REPOSITORIES }}/$repositories/" \
  -e "s/{{ REPOSITORIES_CONTRIBUTED_TO }}/$contributed_to/" \
  -e "s/{{ COMMIT_STREAK }}/$streak/" \
  TEMPLATE.md > README.md
