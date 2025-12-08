# Base image
ARG BASE_IMAGE_TAG="2023"
FROM docker-private.packages.nuxeo.com/nuxeo/nuxeo:${BASE_IMAGE_TAG}

# Build arguments
ARG BUILD_TAG=unknown
ARG SCM_REF=unknown
ARG VERSION=unknown
ARG BUILD_DATE=""
ARG PACKAGES_AUTH_USER
ARG PACKAGES_AUTH_TOKEN
ARG PACKAGES_LIST
ARG NUXEO_CONNECT_MODULES
ARG NODE_VERSION
ARG IMAGE_TITLE="Nuxeo Server"
ARG IMAGE_LICENSE="Apache 2.0"

# Labels
LABEL org.nuxeo.build-tag=$BUILD_TAG \
      org.nuxeo.scm-ref=$SCM_REF \
      org.nuxeo.version=$VERSION \
      org.label-schema.build-date="$BUILD_DATE" \
      org.label-schema.license="$IMAGE_LICENSE" \
      org.label-schema.name="$IMAGE_TITLE" \
      org.label-schema.vendor="$IMAGE_VENDOR" \
      org.opencontainers.image.created="$BUILD_DATE" \
      org.opencontainers.image.licenses="$IMAGE_LICENSE" \
      org.opencontainers.image.title="$IMAGE_TITLE" \
      org.opencontainers.image.vendor="Nuxeo"

# Switch to root
USER root

# Combined system dependencies and secure private repo installation into a single RUN to reduce image layers
# --- Install system dependencies and secure private repo ---
RUN --mount=type=secret,id=nuxeo-private,target=/tmp/nuxeo-private.repo \
    dnf -y install gettext && \
    envsubst </tmp/nuxeo-private.repo >/etc/yum.repos.d/nuxeo-private.repo && \
    dnf -y install --skip-broken $PACKAGES_LIST && \
    rm /etc/yum.repos.d/nuxeo-private.repo && \
    dnf clean all && \
    rm -rf /var/cache/dnf

# Install Node.js if NODE_VERSION is provided
RUN if [ -n "$NODE_VERSION" ]; then \
        curl -fsSL https://rpm.nodesource.com/setup_"$NODE_VERSION".x | bash - && \
        dnf install -y nodejs && \
        dnf clean all && \
        rm -rf /var/cache/dnf; \
    else \
        echo "No Node.js version specified - skipping Node.js installation"; \
    fi

# Install npm packages if a lock file is provided (requires Node.js)
RUN --mount=type=bind,from=npmctx,target=/npmctx \
    if [ -f "/npmctx/package-lock.json" ] && [ -f "/npmctx/package.json" ] && command -v npm >/dev/null 2>&1; then \
        cd /npmctx && \
        npm ci \
    else \
        echo "No package-lock.json or package.json found or npm not installed - skipping npm packages installation"; \
    fi

USER nuxeo

RUN --mount=type=bind,from=modules,target=/modules \
    --mount=type=secret,id=NUXEO_CLID,env=NUXEO_CLID \
    if [ -n "${NUXEO_CONNECT_MODULES}" ]; then \
        /install-packages.sh --clid ${NUXEO_CLID} ${NUXEO_CONNECT_MODULES}; \
    else \
        echo "No Nuxeo Connect modules specified - skipping connect installation"; \
    fi && \
    mods=$(find /modules -maxdepth 1 -type f \( -name '*.zip' -o -name '*.jar' \) -print) && \
    if [ -n "${mods}" ]; then \
        /install-packages.sh --offline ${mods}; \
    else \
        echo "No offline package files (*.zip/*.jar) found in /modules - skipping offline installation"; \
    fi
