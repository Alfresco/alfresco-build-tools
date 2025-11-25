# nuxeo-docker-build

Build and optionally push a customized Nuxeo Docker image layering:

1. Base Nuxeo image (`base-image-tag`).
2. Online Nuxeo Connect modules (`nuxeo-connect-modules`) – requires secret `NUXEO_CLID`.
3. Offline local addon files (`local-addons-path`) – all `.zip`/`.jar` files installed.
4. Optional OS packages (`os-packages`) via private yum repo (`nuxeo-private.repo`).

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `base-image-tag` | false | docker-private.packages.nuxeo.com/nuxeo/nuxeo:2023 | Base image reference |
| `base-registry-username` | true | (none) | Username for base image registry login |
| `base-registry-password` | true | (none) | Password/token for base image registry |
| `nuxeo-connect-modules` | false | "" | Space/comma separated marketplace modules |
| `nuxeo-clid` | false | (none) | Nuxeo Connect License ID (CLID) to use for installing Nuxeo Connect packages |
| `local-addons-path` | false | (empty) | Directory with offline addon archives |
| `os-packages` | false | "" | OS packages to install via private repo |
| `os-packages-user` | false | "" | Yum repo username (if required) |
| `os-packages-token` | false | "" | Yum repo token/password |
| `image-name` | false | `<repo>` | Image name without registry|
| `image-tag` | false | short SHA | Image tag for built image |
| `registry` | false | ghcr.io | Target registry host |
| `registry-username` | false | github.actor | Username for target registry |
| `registry-password` | false | GITHUB_TOKEN | Password/token for target registry |
| `platforms` | false | linux/amd64,linux/arm64 | Build platforms |
| `push-image` | false | false | Push built image (otherwise metadata only) |

## Output

`image-url` – Fully qualified reference: `<registry>/<image-name>:<image-tag>`.

## Example

```yaml
      - name: Build Nuxeo image
        uses: Alfresco/alfresco-build-tools/.github/actions/nuxeo/nuxeo-docker-build@v9.7.1
        with:
          base-image-tag: docker-private.packages.nuxeo.com/nuxeo/nuxeo:2023
          base-registry-username: ${{ secrets.NUXEO_BASE_USER }}
          base-registry-password: ${{ secrets.NUXEO_BASE_PASS }}
          nuxeo-connect-modules: "nuxeo-web-ui nuxeo-drive"
          local-addons-path: addons
          os-packages: "ImageMagick jq"
          image-name: my-nuxeo
          image-tag: ${{ github.sha }}
          push-image: true
        secrets:
          NUXEO_CLID: ${{ secrets.NUXEO_CLID }}
```

Set `push-image: true` on pull requests if you still want to push the image; otherwise it only builds when the workflow event is a push.
