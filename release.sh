#!/bin/bash -e

if ! command -v gh &> /dev/null
then
    echo "gh command should be available for running this script"
    echo "see https://github.com/cli/cli/"
    exit 1
fi

gh auth status

if [ -z "$1" ] || [[ ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo 'First argument should be next version to release with a leading v char'
    exit 1
fi

echo "Switch to master and reset to origin/master (IT WILL WIPE YOUR CURRENT WORK IN PROGRESS)"
read -p "Are you sure? " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

git checkout master
git reset --hard origin/master

CURRENT_VERSION=$(git tag | sort -r --version-sort | head -n1)
echo "Current version is $CURRENT_VERSION"
echo "Going to create a PR to release $1"

git checkout -b "$1"
grep -Rl "$CURRENT_VERSION" | xargs sed -i '' -e "s/$CURRENT_VERSION/$1/g"
grep -Rl "$1" | xargs git add
git commit -m "Prepare to release $1"
git push origin "$1"

gh pr create -a '@me' -t "Release $1" -b ''
git checkout master

echo ""
echo "Once PR is merged execute locally:"
echo "- git pull origin master"
echo "- gh release create $1 --generate-notes -t $1"
echo ""
