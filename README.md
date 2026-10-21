# EcommerceStore LiveDocs — Terraform

Infrastructure for [ECommerceStore.LiveDocs](https://github.com/MichalBoczula/ECommerceStore.LiveDocs):
a static Nginx documentation image plus a private archive of its source bundles.
Deployment is manual. CI validates Terraform and the published image without Azure credentials.

| Root | Owns | Lifetime / backend key |
| --- | --- | --- |
| `archive/` | Dedicated LRS storage account, private `livedocs` container, Products writer and LiveDocs reader identities/RBAC/OIDC | Retained archive; `livedocs/archive.terraform.tfstate` |
| `hosting/` | LiveDocs resource group and one Consumption Container App | Disposable demo; `livedocs/development.terraform.tfstate` |

Both backends use your existing `stecomtfstatemb261011` account and `tfstate`
container. Neither root manages that state account. Different environments need
their own backend keys. There is no Terraform configuration to apply at repository root.

The hosting root reads the existing Products-owned ACA environment, defaulting to
`cae-ecommercestore-products-dev` in `rg-ecommercestore-products-dev`. It creates no
new VNet, subnet, environment, database, Key Vault, registry, or log workspace.
It needs only the shared environment, not a running Products API or SQL connection.

## What happens to documentation

1. Products CI produces a verified ZIP with raw Allure results, features, OpenAPI,
   flows and validation policies, then uploads it and a discovery receipt to Blob.
2. LiveDocs imports a verified candidate through a manifest PR.
3. After review/merge, its image builder downloads private bundles with OIDC,
   validates them, and generates Allure HTML using Python/Java/Allure in the builder.
4. The final image contains only Nginx and completed static files. This Terraform
   deploys its published digest to ACA.

There is **no runtime Blob mount/download**, Node process, Allure server, migration,
or database. Uploading a ZIP does not update an already deployed image: import,
image publication and a reviewed hosting apply are still required.

The inspected published image is
`mb0101/ecommerce-store-livedocs@sha256:05062d11af8cba8e00f7d738037ba53efeb190db398f035cdaa8053f780394d8`,
from commit `a609ca98766b48557e5f5475e8fd223315ca9991`. Its production manifest has
an **empty development v1**, so the example deployment shows navigation, not
Products reports. Update the selected digest intentionally after the first real import.

## Storage decision and review

Use a **dedicated private archive account**, separate from product photos and the
Terraform backend. This keeps the archive alive when Products/photo infrastructure
is destroyed. Reusing an existing account with a new container is technically
possible, but adds lifecycle and storage-policy coupling that this portfolio setup
does not need. This implementation deliberately creates the dedicated archive;
it does not create a second `livedocs` container in Products storage.

The account is Standard LRS with versioning and 30-day Blob/container soft delete,
HTTPS and Entra authentication, no Shared Key, and no anonymous Blob access.
GitHub-hosted runners access its public service endpoint using container-scoped
OIDC roles. No NAT gateway, private endpoint, or storage mount is added.
Versioning/retention can incur storage charges; no blanket expiry deletes retained bundles.

Archive resource group/account/container have `prevent_destroy = true`. Hosting
teardown leaves them intact. Those guards protect Terraform operations while the
configuration remains present; they do not stop an Azure administrator or a Blob
Data Contributor deleting data. They are not WORM retention.

See [the repository review](docs/repository-review.md) for required components,
optional future simplifications, existing setup gaps, and the legacy ownership check.

## 1. Prepare local configuration

Use PowerShell 7, Terraform 1.16.5 and Azure CLI. Both roots pin AzureRM **5.9.0**
and commit official Linux/Windows provider checksums. Your deployment identity
needs resource creation and RBAC assignment permissions, plus access to the
existing Terraform state container.

```powershell
Set-Location D:\Programowanie\Apps\ECommerceStore.LiveDocs.Terraform
$ErrorActionPreference = 'Stop'
$ecommerceTerraform = Join-Path $env:LOCALAPPDATA 'Programs\Terraform\1.16.5\terraform.exe'
if (-not (Test-Path -LiteralPath $ecommerceTerraform)) { throw 'Terraform executable not found' }
az login --output none
if ($LASTEXITCODE -ne 0) { throw 'Azure login failed' }
az account set --subscription 'fcbf086b-8ce4-4ca5-a3d7-0c56489e25f6'
if ($LASTEXITCODE -ne 0) { throw 'Subscription selection failed' }

foreach ($root in @('archive', 'hosting')) {
    if (-not (Test-Path ".\$root\backend.hcl")) {
        Copy-Item ".\$root\backend.hcl.example" ".\$root\backend.hcl"
    }
    if (-not (Test-Path ".\$root\terraform.tfvars")) {
        Copy-Item ".\$root\terraform.tfvars.example" ".\$root\terraform.tfvars"
    }
}
```

Review the files before initialization. Keep existing suffixes stable. Read
[the legacy archive check](docs/repository-review.md#existing-archive-and-state)
before applying `archive/` if the old `foundations/livedocs` was ever deployed.
Do not manage one existing archive from two states or create a replacement for
retained manifest URLs without a migration plan.

## 2. Provision the private archive

```powershell
& $ecommerceTerraform '-chdir=archive' init '-backend-config=backend.hcl'
if ($LASTEXITCODE -ne 0) { throw 'Archive initialization failed' }
& $ecommerceTerraform '-chdir=archive' fmt '-check' '-recursive'
if ($LASTEXITCODE -ne 0) { throw 'Archive formatting failed' }
& $ecommerceTerraform '-chdir=archive' validate
if ($LASTEXITCODE -ne 0) { throw 'Archive validation failed' }
& $ecommerceTerraform '-chdir=archive' test
if ($LASTEXITCODE -ne 0) { throw 'Archive mocked tests failed' }
& $ecommerceTerraform '-chdir=archive' plan '-input=false' '-out=archive.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Archive planning failed' }
```

For a fresh state, expect **8 additions** with the example inputs. Reader
federation is initially disabled. An optional operator reader adds one resource;
enabling both protected reader federations adds two. Review the plan, then apply:

```powershell
& $ecommerceTerraform '-chdir=archive' apply archive.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Archive apply failed; retain state and inspect the error' }
$archiveJson = (& $ecommerceTerraform '-chdir=archive' output -json archive_configuration) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Archive output lookup failed' }
$archive = $archiveJson | ConvertFrom-Json
$archive | Format-List
```

These outputs contain IDs, not Azure client secrets. Follow
[GitHub archive setup](docs/github-setup.md) before enabling publication/import.
RBAC and federation can need propagation time. Do not fall back to account keys
or SAS tokens when a newly assigned role has not propagated.

## 3. Deploy the static host

The example explicitly opts into anonymous public HTTPS for the portfolio. The
variable default is internal ingress; choose deliberately in `hosting/terraform.tfvars`.
A private archive does **not** make content inside a public Docker Hub image
confidential. Publish only documentation/attachments intended for that audience.

For the first demonstration, temporarily set `min_replicas = 1`; restore zero
after verification. The cap is always one replica, at 0.25 vCPU / 0.5 GiB.

```powershell
& $ecommerceTerraform '-chdir=hosting' init '-backend-config=backend.hcl'
if ($LASTEXITCODE -ne 0) { throw 'Hosting initialization failed' }
& $ecommerceTerraform '-chdir=hosting' fmt '-check' '-recursive'
if ($LASTEXITCODE -ne 0) { throw 'Hosting formatting failed' }
& $ecommerceTerraform '-chdir=hosting' validate
if ($LASTEXITCODE -ne 0) { throw 'Hosting validation failed' }
& $ecommerceTerraform '-chdir=hosting' test
if ($LASTEXITCODE -ne 0) { throw 'Hosting mocked tests failed' }
& $ecommerceTerraform '-chdir=hosting' plan '-input=false' '-out=hosting.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Hosting planning failed' }
```

Expect **two additions** for a fresh hosting state and a read-only environment
lookup. Review, then apply and verify the external example:

```powershell
& $ecommerceTerraform '-chdir=hosting' apply hosting.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Hosting apply failed; retain state and inspect the error' }
$deploymentJson = (& $ecommerceTerraform '-chdir=hosting' output -json livedocs_deployment) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Hosting output lookup failed' }
$deployment = $deploymentJson | ConvertFrom-Json
$deployment | Format-List

$ready = Invoke-WebRequest "$($deployment.base_url)/health/ready" -TimeoutSec 30
if ($ready.StatusCode -ne 200) { throw 'LiveDocs is not ready' }
$build = Invoke-RestMethod "$($deployment.base_url)/build-info.json" -TimeoutSec 30
$build | Format-List
$portal = Invoke-RestMethod "$($deployment.base_url)/livedoc/catalog.json" -TimeoutSec 30
$portal | ConvertTo-Json -Depth 8
Start-Process $deployment.documentation_url
```

Compare `build.commitSha` with the source commit recorded by the selected image's
publication metadata. The example uses `a609ca98766b48557e5f5475e8fd223315ca9991`.
The empty example catalog is expected; require real Products entries after import.
Cold starts can require a retry. For internal ingress, run checks from a container
in the same ACA environment; the URL can return Azure's 404 from your laptop.

The application uses HTTP 8080 internally, `/health/live` for startup/liveness,
and `/health/ready` for readiness. Preserve the full `/livedoc/` path. No SPA
fallback, BFF proxy, `/api` prefix, or SQL readiness check is needed.

For logs, use `az containerapp logs show` with the output resource group/name.
System logs require `--type system --format json`; console logs support
`--type console --format text`. No additional retained log storage is provisioned.
An app at zero replicas needs a request to wake it or a temporary minimum of one
before attaching a console. Keep Terraform responsible for that scaling setting.

## 4. Update reports and destroy the demo host

Complete the real Products archive/import flow, merge its manifest PR, and wait
for a new scanned/published LiveDocs image. Change only `livedocs_image` to that
digest, create/review a new hosting plan, and apply it. Verify commit identity and
the version/project/Allure pages; a successful Blob upload alone is insufficient.

After capturing the portfolio material, destroy **hosting only**, before destroying
the shared Products environment. BFF/web teardown remains in their own roots.

```powershell
& $ecommerceTerraform '-chdir=hosting' plan '-destroy' '-input=false' '-out=hosting-destroy.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Hosting destroy planning failed' }
```

Review: only the LiveDocs app and hosting resource group should be deleted.

```powershell
& $ecommerceTerraform '-chdir=hosting' apply hosting-destroy.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Hosting destroy failed; keep state and inputs' }
& $ecommerceTerraform '-chdir=hosting' state list
if ($LASTEXITCODE -ne 0) { throw 'Hosting state verification failed' }
```

No managed hosting resources should remain. A data lookup in state is not resource
ownership. Keep both backend blobs, the archive root/resources, and original input
bundles. Scale-to-zero removes idle replica usage, not archive/network/storage
charges. The separate archive retains storage charges until it is deliberately retired.

`archive/` is intentionally not part of demo destruction. Retiring it means
exporting every supported bundle and receipt, disabling producer/import access,
then reviewing removal of its `prevent_destroy` guards and an archive-specific
destroy plan. Do not remove guards merely to destroy an ACA demo.

## Checks

CI initializes each root with `-backend=false -lockfile=readonly`, validates the
provider schema and runs mocked plans with deliberately conflicting local input
files. The explicit test baselines prevent the rollout-file collision seen in
the earlier Products tests. CI also runs the source repository's actual Docker
smoke contract against the digest-pinned published image, including readiness
503 with missing content. No CI job provisions Azure or changes a revision.

Provider reference: [AzureRM 5.9.0](https://github.com/hashicorp/terraform-provider-azurerm/tree/v5.9.0).
Platform references: [ACA probes](https://learn.microsoft.com/en-us/azure/container-apps/health-probes),
[GitHub OIDC environments](https://docs.github.com/en/actions/how-tos/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure).
