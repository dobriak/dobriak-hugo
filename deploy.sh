#!/bin/bash
#set -ex
echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# Build the project.
hugo --theme=hugo-theme-pixyll

if [ ! -d ../dobriak.github.io ]; then
  pushd ../
    git clone git@github.com:dobriak/dobriak.github.io.git
  popd
fi

# Operate on the github.io level repo
pushd ../dobriak.github.io
  git pull origin
  rm -rf *
  cp -r ../dobriak-hugo/public/* ./
  git add .
  msg="rebuilding site `date`"
  if [ $# -eq 1 ]
    then msg="$1"
  fi
  git commit -am "$msg"
  git push origin master
popd
echo "Done"
