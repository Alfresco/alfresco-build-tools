# alfresco-build-tools

[![Build Status](https://travis-ci.com/Alfresco/alfresco-build-tools.svg?branch=master)](https://travis-ci.com/Alfresco/alfresco-build-tools)
[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)

Shared [Travis CI](https://travis-ci.com/) and [pre-commit](https://pre-commit.com/) configuration files plus misc tools.

## GitHub Actions

### setup-helm

If you need the helm cli available in the runner path:

```yml
jobs:

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v1
      - uses: Alfresco/alfresco-build-tools/.github/actions/setup-helm@master
```
