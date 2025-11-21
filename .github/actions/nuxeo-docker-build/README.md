# Nuxeo Docker Build Action

This action builds a custom Nuxeo Docker image with packages from Nuxeo Connect and/or local addon files.

## Features

- Uses any Nuxeo base image as a starting point
- Installs packages from Nuxeo Connect (with authentication)
- Installs local addon JARs/ZIPs
- Allows custom Dockerfile instructions
- Supports multi-platform builds (amd64, arm64)
- Pushes to any container registry (GHCR, Quay, Docker Hub, or custom)

## Usage

### Basic Example

```yaml
- uses: Alfresco/alfresco-build-tools/.github/actions/nuxeo-docker-build@vX.Y.Z
  with:
    base-image: nuxeo:2023
    registry-password: ${{ secrets.GITHUB_TOKEN }}
```

### With Nuxeo Connect Packages

```yaml
- uses: Alfresco/alfresco-build-tools/.github/actions/nuxeo-docker-build@vX.Y.Z
  with:
    base-image: docker.packages.nuxeo.com/nuxeo/nuxeo:2023.x
    nuxeo-connect-username: ${{ secrets.NUXEO_CONNECT_USERNAME }}
    nuxeo-connect-password: ${{ secrets.NUXEO_CONNECT_PASSWORD }}
    nuxeo-packages: "nuxeo-web-ui nuxeo-platform-3d nuxeo-dam"
    registry-password: ${{ secrets.GITHUB_TOKEN }}
```

### With Local Addons

```yaml
- name: Build Maven project
  run: mvn clean package

- uses: Alfresco/alfresco-build-tools/.github/actions/nuxeo-docker-build@vX.Y.Z
  with:
    base-image: nuxeo:2023
    local-addons: "target/my-nuxeo-addon-1.0.0.jar"
    registry-password: ${{ secrets.GITHUB_TOKEN }}
```

### With Custom Dockerfile

```yaml
- uses: Alfresco/alfresco-build-tools/.github/actions/nuxeo-docker-build@vX.Y.Z
  with:
    base-image: nuxeo:2023
    custom-dockerfile: docker/custom-instructions.dockerfile
    registry-password: ${{ secrets.GITHUB_TOKEN }}
```

### Complete Example

```yaml
jobs:
  build-nuxeo-image:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Build addon
        run: mvn clean package -DskipTests

      - uses: Alfresco/alfresco-build-tools/.github/actions/nuxeo-docker-build@vX.Y.Z
        with:
          base-image: docker.packages.nuxeo.com/nuxeo/nuxeo:2023.x
          nuxeo-connect-username: ${{ secrets.NUXEO_CONNECT_USERNAME }}
          nuxeo-connect-password: ${{ secrets.NUXEO_CONNECT_PASSWORD }}
          nuxeo-packages: "nuxeo-web-ui nuxeo-dam"
          local-addons: "target/my-addon-1.0.0.jar custom-packages/other-addon.zip"
          custom-dockerfile: docker/custom.dockerfile
          image-name: my-custom-nuxeo
          image-tag: ${{ github.ref_name }}
          registry: ghcr.io
          registry-password: ${{ secrets.GITHUB_TOKEN }}
          platforms: linux/amd64,linux/arm64
          labels: |
            org.opencontainers.image.description=My Custom Nuxeo Platform
            maintainer=devops@example.com
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `base-image` | Base Nuxeo Docker image tag | Yes | - |
| `nuxeo-connect-username` | Nuxeo Connect username | No | - |
| `nuxeo-connect-password` | Nuxeo Connect password | No | - |
| `nuxeo-packages` | Space-separated list of Nuxeo packages from Connect | No | - |
| `local-addons` | Space-separated list of local addon files | No | - |
| `custom-dockerfile` | Path to custom Dockerfile with additional instructions | No | - |
| `base-directory` | Base working directory | No | `.` |
| `image-name` | Name of the output image (without tag) | No | Repository name |
| `image-tag` | Tag for the output image | No | Sanitized branch/tag name |
| `registry` | Container registry to push to | No | `ghcr.io` |
| `registry-username` | Registry username | No | `${{ github.actor }}` |
| `registry-password` | Registry password/token | Yes | - |
| `push` | Whether to push the built image | No | `true` |
| `platforms` | Comma-separated list of platforms | No | `linux/amd64` |
| `build-args` | Additional build arguments (newline-separated) | No | - |
| `labels` | Additional image labels (newline-separated) | No | - |

## Outputs

| Output | Description |
|--------|-------------|
| `image-url` | Full URL of the built image |
| `image-tag` | The tag used for the image |
| `image-digest` | The digest of the pushed image |

## Notes

- If using Nuxeo Connect packages, both `nuxeo-connect-username` and `nuxeo-connect-password` must be provided
- Local addon files are copied to `/opt/nuxeo/server/nxserver/bundles/`
- The custom Dockerfile should contain only additional instructions (no FROM statement)
- The action automatically switches to the nuxeo user (1000) at the end of the Dockerfile
- Multi-platform builds require the platforms to be comma-separated without spaces

## Example Custom Dockerfile

If you need additional customizations, create a file like `docker/custom.dockerfile`:

```dockerfile
# Install additional system packages
RUN apt-get update && apt-get install -y \
    imagemagick \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Add custom configuration
COPY nuxeo.conf /etc/nuxeo/nuxeo.conf

# Set custom environment variables
ENV NUXEO_TEMPLATES=default,mongodb
```

Then reference it in your workflow with `custom-dockerfile: docker/custom.dockerfile`.
