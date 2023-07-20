#!/bin/bash
# shellcheck shell=bash

set -e

current_version=$(ruby -e "require '$(pwd)/lib/canvas_link_migrator/version.rb'; puts CanvasLinkMigrator::VERSION;")
existing_versions=$(gem list --exact canvas_link_migrator --remote --all | grep -o '\((.*)\)$' | tr -d '() ')

if [[ $existing_versions == *$current_version* ]]; then
  echo "Gem has already been published ... skipping ..."
else
  gem build ./canvas_link_migrator.gemspec
  find canvas_link_migrator-*.gem | xargs gem push
fi
