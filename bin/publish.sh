#!/bin/bash
# shellcheck shell=bash

set -e

current_version=$(ruby -e "require '$(pwd)/lib/canvas_link_migrator/version.rb'; puts CanvasLinkMigrator::VERSION;")
existing_versions=$(gem list --exact canvas-link-migrator --remote --all | grep -o '\((.*)\)$' | tr -d '() ')

if [[ $existing_versions == *$current_version* ]]; then
  echo "Gem has already been published ... skipping ..."
else
  gem build ./canvas-link-migrator.gemspec
  find canvas-link-migrator-*.gem | xargs gem push
fi
