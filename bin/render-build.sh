#!/usr/bin/env bash
set -o errexit

# Ensure a SECRET_KEY_BASE is present for asset compilation
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-dummy}"

bundle install
bundle exec rake assets:precompile
bundle exec rake assets:clean 
bundle exec rails assets:precompile
bundle exec rails assets:clean
