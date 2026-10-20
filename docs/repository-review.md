# LiveDocs review and infrastructure boundary

Reviewed source commit: `a609ca98766b48557e5f5475e8fd223315ca9991`.
Reviewed the Dockerfile, Nginx config, manifests, schemas, generator/archive/import
scripts, CI/reusable workflows, container contract and architecture decisions.
This review does not inspect live Azure resources or GitHub secret values.

## Findings

| Finding | Consequence / action |
| --- | --- |
| The final image is non-root Nginx, not Node or an Allure application server | One small ACA container is enough; no runtime database, storage identity, volume, Java or Python is needed. |
| Allure HTML is assembled before image publication | Uploading reports to Blob does not refresh the site. Preserve the existing ZIP → manifest PR → image → Terraform flow. |
| Production `manifests/portal.json` contains an empty v1 | The current image serves navigation but no Products report. Do not use fixture reports to claim production integration is working. |
| Producer/import/read-access tooling already exists | Missing deployment pieces are Azure archive/identities and GitHub environment/App/variable setup, followed by a real archive/import run. |
| Source instructions point to `ECommerceStore.Infrastructure`, now renamed `-DEPRECATED-ECommerceStore.Infrastructure` | New Azure ownership belongs here. A companion source documentation PR updates current instructions and adds an ownership ADR. |
| Existing deprecated infrastructure includes `foundations/livedocs` | Its presence is not proof of an applied archive. Check state/resources before adopting or provisioning; never give the same resource two Terraform owners. |
| Runtime hosting and archive lifetimes differ | Two small Terraform roots keep demo destruction away from retained documentation inputs. |
| Public Docker images embed generated report content | A private archive or internal ACA ingress cannot make those image bytes confidential. Review attachments for the intended publication audience. |

## Which code is required?

The source has about 1,550 Python lines across build/delivery tooling and tests;
the running web server is a short Nginx configuration. Treating all those lines
as runtime application complexity would give the wrong picture.

| Component | Why retain it |
| --- | --- |
| Dockerfile, `nginx/`, minimal `site/` | Static host, health, redirects and actual 404 behavior. |
| `scripts/livedocs.py`, manifests, JSON schemas | Safe extraction, file/source identity, retained versions, consistent generation and atomic output. These protect historical reports and prevent partial snapshots. |
| `delivery.py`, packaging/archive/fetch wrappers | Existing GitHub Actions entry points; authentication and bundle transfer occur outside Docker. Most wrappers are small CLI adapters rather than duplicate implementations. |
| Import workflow/tooling | Turns uploaded receipts into reviewed manifest changes and verifies successful producer provenance. Required for the chosen reviewed import flow. |
| Assembly, hosting and integration tests | Cover corrupt archives, attachments, immutable releases, idempotent uploads and workflow publication boundaries. Do not remove them just to reduce line count. |
| `ci.sh`, smoke checks, quality gate | Shared local/CI commands and proof that the published container is the tested one. |

Nothing in this review justifies deleting the generator or introducing Node.
Optional simplifications are product decisions: disable scheduled imports and run
them manually; support fewer projects/versions if history is no longer required;
or serve only already-generated static HTML if provenance/rebuild guarantees are
deliberately dropped. The scheduler is already opt-in. This change adds no new
application framework, generic module hierarchy or deployment workflow.

## Existing archive and state

The deprecated root defines `rg-ecommerce-livedocs-archive`, a deterministic
`stecomld...` storage account, the `livedocs` container, identities, role assignments
and a management lock. Many have `prevent_destroy`. This new root uses distinct
names for a **fresh archive**, appropriate while the inspected production manifest
is empty. It does not silently import, delete, unlock, move or copy old resources.

If the old root was applied:

1. Locate and back up its actual backend/state; inspect Azure resource IDs and
   the current workflows' configured archive account. Do not guess the old key.
2. Check all retained manifests for existing Blob URLs and inventory referenced
   ZIPs/receipts. URLs in released manifests are part of the retained contract.
3. Choose a reviewed state migration/adoption preserving the existing physical
   account, URLs, names and lock. Adjust this root's names/addresses first; moving
   only a backend is insufficient because this configuration's resource names
   and addresses differ. Account for every old role/lock/identity too.
4. Transfer ownership exactly once and require a plan without data deletion or
   account replacement before enabling writer/import changes.

Do not run two roots against the same archive or repoint active workflows to an
empty new account. A storage account existing in Azure does not justify `state rm`.
A live migration is separate from this new-stack implementation and needs the
actual existing state/resource information.

## Validation boundaries

Source assembly and hosting suites can run locally without Azure. The source
generator's existing 70% coverage floor remains intact. Terraform CI uses mocked
providers and the pinned published image's real Docker HTTP contract. These
checks do not claim live Azure RBAC propagation, protected environment setup,
successful real producer upload, or a deployed nonempty Allure report.
