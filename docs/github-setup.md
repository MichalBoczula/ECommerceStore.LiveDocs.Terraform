# GitHub archive setup

Terraform creates Azure resources and OIDC federation, not repository secrets,
GitHub Apps, protected environments, automatic workflow runs, or deployments.
All identifiers come from `archive_configuration` in the archive root.

## Protect the reader subjects first

In `MichalBoczula/ECommerceStore.LiveDocs`, configure:

| GitHub environment | Required policy |
| --- | --- |
| `livedocs-archive-build` | Selected deployment branches: `main`, plus only explicitly supported version branches. Do not allow PR merge refs. |
| `livedocs-archive-pr` | Required authorized reviewer; disable administrator bypass; allow trusted internal PR merge refs (`refs/pull/*/merge`). Keep self-review available for Mike's own PRs if required. |

Approve archive-read jobs only for reviewed internal PR code. Fork PRs are refused
by the checked-in workflow. Terraform trusts exact environment subjects, not a
bare `pull_request` subject. Environment rules protect token issuance; a condition
inside PR-editable workflow YAML is not a substitute.

Then set `enable_reader_federation = true` in `archive/terraform.tfvars`, create
and review a fresh archive plan, and apply it. It adds the two reader credentials.
This assertion is an operator-controlled setup flag, not an automated GitHub
environment policy verifier.

The Products writer is restricted to
`repo:MichalBoczula/ProductsCatalog:ref:refs/heads/master`. The reader uses
`repo:MichalBoczula/ECommerceStore.LiveDocs:environment:livedocs-archive-build`
and the matching `livedocs-archive-pr` subject. Both use issuer
`https://token.actions.githubusercontent.com` and audience `api://AzureADTokenExchange`.
Neither identity is attached to the ACA host.

## Set repository variables

| Variable | ProductsCatalog | ECommerceStore.LiveDocs |
| --- | --- | --- |
| `AZURE_SUBSCRIPTION_ID` | `subscription_id` | Same |
| `AZURE_TENANT_ID` | `tenant_id` | Same |
| `LIVEDOCS_STORAGE_ACCOUNT` | `storage_account_name` | Same |
| `LIVEDOCS_AZURE_CLIENT_ID` | `products_writer_client_id` | `reader_client_id` |
| `LIVEDOCS_VERSION` | `v1` initially | — |
| `LIVEDOCS_PUBLISH_ENABLED` | `true` after Azure setup | — |
| `LIVEDOCS_IMPORT_ENABLED` | — | Keep off until the first manual import succeeds |
| `LIVEDOCS_IMPORT_VERSION` | — | `v1` |
| `LIVEDOCS_IMPORT_BRANCH` | — | `main` |
| `LIVEDOCS_APP_ID` | — | Repository-scoped GitHub App ID |

Create a GitHub App installed only in LiveDocs with Contents and Pull requests
read/write. Store its private key as `LIVEDOCS_APP_PRIVATE_KEY` in LiveDocs.
The importer needs this App token to open a PR that triggers normal PR checks;
the default `GITHUB_TOKEN` does not trigger those events. No producer PAT or
cross-repository write access is required.

Keep existing Docker Hub publication secrets. Azure OIDC uses IDs rather than a
client secret or SAS. The Azure writer/reader have Blob data roles on `livedocs`
only; they cannot deploy ACA or modify Products photos. Blob Data Contributor
does permit deletes, so application no-overwrite checks are not a WORM boundary.

## Verify the first real handoff

1. Enable Products publication only after archive access is ready. A new successful
   master push must pass service checks and scanned image publication before its
   archive job uploads the ZIP and discovery receipt.
2. In LiveDocs run **Import documentation** manually from main, choosing existing
   development version `v1` and target branch `main`.
3. Review the manifest PR and approve its private archive-read job only after
   reviewing its code. Require the complete existing LiveDocs CI.
4. Merge the PR and wait for the tested/scanned image publication. Set the hosting
   input to its immutable digest and review/apply the hosting plan.
5. Verify `/build-info.json`, `/livedoc/v1/products/` and the project's `allure/`
   assets. Then opt into scheduled imports if wanted.

The scheduler opens candidates; it does not merge or deploy. Preserve every bundle
referenced by retained versions. Only synthetic, publication-safe test data belongs
in report attachments, since generated content is embedded in a public image.
