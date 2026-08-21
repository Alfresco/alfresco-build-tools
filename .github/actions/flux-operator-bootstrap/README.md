# flux-operator-bootstrap

Bootstraps or uninstalls [Flux](https://fluxcd.io/) on a Kubernetes cluster using the
[Flux Operator](https://github.com/controlplaneio-fluxcd/flux-operator), driving it through a
`FluxInstance` custom resource rather than the imperative `flux bootstrap` command.

## Prerequisites

The action is cloud agnostic and starts from the Flux CLI setup onwards. It assumes `kubectl` is already
pointing at the target cluster, so the calling workflow owns cloud authentication and the kubeconfig. This
keeps cloud specific credentials out of the action and lets the same action serve AKS, EKS, GKE and local
clusters.

### AKS

```yaml
      - uses: azure/login@a65d910e8af852a8061c627c456678983e180302 # v2.2.0
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Pull kubeconfig
        env:
          AZURE_RESOURCE_GROUP: my-resource-group
          CLUSTER_NAME: ${{ vars.RESOURCE_NAME }}
        run: |
          az aks get-credentials \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --name "$CLUSTER_NAME" \
            --overwrite-existing

      - uses: Alfresco/alfresco-build-tools/.github/actions/flux-operator-bootstrap@v18.24.1
        with:
          cluster-type: azure
          # ...
```

### EKS

```yaml
      - uses: aws-actions/configure-aws-credentials@e6de054238d6b7531b4efff3b6587d9aade6a06c # v6.2.3
        with:
          aws-region: eu-west-1
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}

      - name: Pull kubeconfig
        env:
          AWS_REGION: eu-west-1
          CLUSTER_NAME: ${{ vars.RESOURCE_NAME }}
        run: |
          aws eks update-kubeconfig \
            --region "$AWS_REGION" \
            --name "$CLUSTER_NAME"

      - uses: Alfresco/alfresco-build-tools/.github/actions/flux-operator-bootstrap@v18.24.1
        with:
          cluster-type: aws
          # ...
```

Assuming a role through OIDC needs `permissions: id-token: write` on the job. Passing
`aws-access-key-id` and `aws-secret-access-key` instead works the same way for the kubeconfig, and the
caller's IAM principal must be mapped in the cluster's access entries or `aws-auth` config map.

Set `cluster-type` to match the platform (`azure`, `aws`, `gcp`, `openshift` or `kubernetes`) so the
operator applies the right platform specific defaults.

## Repository access

The `FluxInstance` authenticates against the Git repository with a GitHub App. The action creates the
`flux-system` secret in the `flux-system` namespace from the `github-app-*` inputs on every bootstrap, so
rotating the App key only requires re-running the workflow. The GitHub App needs read access to the
repository passed as `sync-url`.

The private key is written to a `mktemp` file that is removed by an `EXIT` trap, so it is cleaned up even
when the `flux create secret` call fails.

## Opinionated defaults

To keep the interface small, the following are fixed rather than exposed as inputs: the `flux-system`
namespace, the `flux` instance name, the `flux-operator` Helm release name and chart, the `ghcr.io/fluxcd`
registry, the `2.x` distribution range, the full set of six Flux controllers, `multitenant: false`,
`networkPolicy: true` and the `cluster.local` domain. Callers needing to vary any of these should raise a
PR to promote it to an input.

## Bootstrap and uninstall

`action: uninstall` deletes the `FluxInstance` and uninstalls the operator Helm release, and ignores every
other input. Both branches are idempotent: uninstalling a cluster that never had Flux is a no-op, and
bootstrapping an already bootstrapped cluster reconciles it to the desired state.

The Flux CLI version is not an input: it follows the default of
[setup-fluxcli](https://github.com/Alfresco/alfresco-build-tools/blob/master/.github/actions/setup-fluxcli/action.yml),
which updatecli keeps current. Callers needing a specific version can run `setup-fluxcli` themselves
beforehand.
