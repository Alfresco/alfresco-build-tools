# nuxeo-docker-build

Build and optionally push a customized Nuxeo Docker image layering:

1. Base Nuxeo image (argument `base-image-tag`).
2. Online Nuxeo Connect modules (`nuxeo-connect-modules`) – requires secret `NUXEO_CLID`.
3. Offline local addon files (`local-addons-path`) – all `.zip`/`.jar` files are installed.
4. Optional OS packages (`os-packages`) via the private yum repository template (`nuxeo-private.repo`).

## Inputs

- `base-image-tag` (required): Base image reference (e.g. `docker-private.packages.nuxeo.com/nuxeo/nuxeo:2023`).
- `nuxeo-connect-modules`: Space/comma separated marketplace modules to install online.
- `local-addons-path`: Directory containing offline addon archives (default `addons`).
- `os-packages`: Space separated OS packages to install (optional).
- `image-name`: Image name (without registry). Defaults to `<repo>-nuxeo`.
- `image-tag`: Image tag. Defaults to sanitized ref or short SHA.
- `registry`: Target registry (default `ghcr.io`).
- `platforms`: Multi-arch platforms (default `linux/amd64`).
- `push-image`: Override push policy (default: only push on `push` events).

## Secrets

- `NUXEO_CLID`: Mandatory if `nuxeo-connect-modules` provided.
- Optionally any auth required for the base image pull (handled externally).

## Output

- `image-url`: Fully qualified image reference (`registry/alfresco/<image-name>:<image-tag>`).

## Example

```yaml
      - name: Build Nuxeo image
        uses: Alfresco/alfresco-build-tools/.github/actions/nuxeo-docker-build@v9.7.0
        with:
          base-image-tag: docker-private.packages.nuxeo.com/nuxeo/nuxeo:2023
          nuxeo-connect-modules: "nuxeo-web-ui nuxeo-drive"
          local-addons-path: addons
          os-packages: "ImageMagick jq"
          image-name: my-nuxeo
          image-tag: ${{ github.sha }}
        secrets:
          NUXEO_CLID: ${{ secrets.NUXEO_CLID }}
```

If `push-image` is not set the action pushes only on `push` events. Set `push-image: true` to force pushing on PRs.
