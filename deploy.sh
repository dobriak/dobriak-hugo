#!/bin/bash
set -ex
echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# Build the project.
hugo --theme=hugo-theme-pixyll

if [ ! -d ../dobriak.github.io ]; then
  pushd ../
  git clone git@github.com:dobriak/dobriak.github.io.git
  popd
fi

rm -rf ../dobriak.github.io/*
cp -r public/* ../dobriak.github.io
pushd ../dobriak.github.io
# Add changes to git.
git add .
# Commit changes.
msg="rebuilding site `date`"
if [ $# -eq 1 ]
  then msg="$1"
fi
git commit -am "$msg"
# Push source and build repos.
git push origin master
# Come Back
popd
echo "Done"