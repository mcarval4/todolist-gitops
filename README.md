# TodoList GitOps

This repository is the source of truth for the TodoList deployment. Argo CD reconciles the local
environment from `bootstrap/todolist-local.yaml`.

Application releases update only `environments/local/todolist-values.yaml` through a pull request.
The image digest, rather than a mutable tag, identifies the deployed application version.

## Layout

- `apps/todolist/chart`: Helm chart for the TodoList workload.
- `environments/local`: image promotion values and local environment resources.
- `bootstrap`: Argo CD Application definitions.
- `tests` and `scripts`: post-sync checks executed by the local deployment runner.

## Local Validation

```bash
helm lint apps/todolist/chart
helm template todolist apps/todolist/chart --values environments/local/todolist-values.yaml
```

The local runner requires a ready `todolist-demo` kind cluster. It is provisioned by
`mcarval4/todolist-platform`.

After all deployment checks pass, `Deploy And Verify Local Platform` uses a short-lived GitHub
App token to notify `todolist-app`. That repository creates the tag and GitHub Release at the
validated source revision. Configure `TODOLIST_AUTOMATION_APP_ID` and
`TODOLIST_AUTOMATION_APP_PRIVATE_KEY` as Actions secrets in this repository.
