# GitHub GraphQL Mutations Reference

All mutations use `gh api graphql`. This file documents the exact mutations needed for the skill.

## Create Label

```bash
gh api graphql -f query='
  mutation($repoId: ID!, $name: String!, $color: String!, $description: String) {
    createLabel(input: {repositoryId: $repoId, name: $name, color: $color, description: $description}) {
      label { id name }
    }
  }
' -f repoId="$REPO_ID" -f name="$LABEL_NAME" -f color="$COLOR" -f description="$DESC"
```

Color is 6-char hex WITHOUT the `#` prefix (e.g., `1f8cf9`).

## Create Issue with Issue Type

```bash
gh api graphql -f query='
  mutation($repoId: ID!, $title: String!, $body: String!, $issueTypeId: ID!, $labelIds: [ID!]) {
    createIssue(input: {repositoryId: $repoId, title: $title, body: $body, issueTypeId: $issueTypeId, labelIds: $labelIds}) {
      issue { id number url }
    }
  }
' -f repoId="$REPO_ID" -f title="$TITLE" -f body="$BODY" -f issueTypeId="$TYPE_ID" -f labelIds='["'$LABEL_ID'"]'
```

## Add Sub-Issue (Parent-Child Relationship)

```bash
gh api graphql -f query='
  mutation($parentId: ID!, $childId: ID!) {
    addSubIssue(input: {issueId: $parentId, subIssueId: $childId}) {
      issue { id }
      subIssue { id }
    }
  }
' -f parentId="$PARENT_ID" -f childId="$CHILD_ID"
```

## Add Issue to Project

```bash
gh api graphql -f query='
  mutation($projectId: ID!, $contentId: ID!) {
    addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) {
      item { id }
    }
  }
' -f projectId="$PROJECT_ID" -f contentId="$ISSUE_ID"
```

Returns the `item.id` which is the project item ID (needed for setting fields).

## Set Project Field Value (SingleSelect)

```bash
gh api graphql -f query='
  mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $projectId,
      itemId: $itemId,
      fieldId: $fieldId,
      value: {singleSelectOptionId: $optionId}
    }) {
      projectV2Item { id }
    }
  }
' -f projectId="$PROJECT_ID" -f itemId="$ITEM_ID" -f fieldId="$FIELD_ID" -f optionId="$OPTION_ID"
```

## Get Repository ID

```bash
gh api graphql -f query='
  query($owner: String!, $name: String!) {
    repository(owner: $owner, name: $name) {
      id
      issueTypes(first: 20) { nodes { id name } }
      labels(first: 100) { nodes { id name } }
      projectsV2(first: 5) {
        nodes {
          id title
          fields(first: 30) {
            nodes {
              ... on ProjectV2SingleSelectField { id name options { id name } }
              ... on ProjectV2Field { id name }
            }
          }
        }
      }
    }
  }
' -f owner="$OWNER" -f name="$REPO"
```
