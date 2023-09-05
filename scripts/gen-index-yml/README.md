# Generate a yaml index from subfolders in a folder

This is a quick script which can enumerate subfolders inside a given folder and
generate/update a yaml which contains a dictionary where each entry is a subfolder name.

Can be used in GitHub Actions matrix workflows to generate the list to iterate.

Can be hooked in pre-commit as a local hook with:

```yaml
  - repo: local
    hooks:
    -   id: update-index-yml
        name: update charts.yml file
        language: docker_image
        entry: ghcr.io/alfresco/build-tools-gen-index-yml:master
        pass_filenames: false
```
