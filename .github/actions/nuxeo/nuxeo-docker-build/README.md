# nuxeo-docker-build

Build and optionally push a customized Nuxeo Docker image layering:

1. Base Nuxeo image (`base-image-tag`).
2. Online Nuxeo Connect modules (`nuxeo-connect-modules`) – requires secret `NUXEO_CLID`.
3. Offline local addon files (`nuxeo-local-modules-path`) – all `.zip`/`.jar` files installed.
4. Optional OS packages (`os-packages`) via private yum repo (`nuxeo-private.repo`).

Pushes the resulting image to a target registry (default `ghcr.io`) and outputs the full image URL.

```yaml
      - name: Build Nuxeo image
        uses: Alfresco/alfresco-build-tools/.github/actions/nuxeo/nuxeo-docker-build@v10.1.0
        with:
          base-image-tag: 2023
          base-registry-username: ${{ secrets.NUXEO_REGISTRY_USERNAME }}
          base-registry-password: ${{ secrets.NUXEO_REGISTRY_PASSWORD }}
          nuxeo-connect-modules: "nuxeo-web-ui nuxeo-drive" # optional
          nuxeo-clid: ${{ secrets.NUXEO_CLID }} # optional if nuxeo-connect-modules is empty
          nuxeo-local-modules-path: addons # directory with offline addon zips
          os-packages: "ImageMagick jq" # optional
          image-name: my-nuxeo-custom
          image-tag: ${{ github.sha }}
          registry: ghcr.io
          registry-username: ${{ secrets.GITHUB_USERNAME }}
          registry-password: ${{ secrets.GITHUB_TOKEN }}
```

## Inputs

Check `action.yml` for the full list of inputs and their descriptions.

## Outputs

- The composite action sets output `image-url` to the fully qualified reference.

## Notes

- If no connect modules are provided, that phase is skipped.
- If the addons directory does not exist it is created empty (offline install skipped).
- Set `push-image: true` to push the image to the target registry.
- Provide private yum repo credentials via inputs (`os-packages-user`, `os-packages-token`) if needed (templated by `nuxeo-private.repo`).
