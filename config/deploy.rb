set :stages, %w(production)
set :default_stage, 'production'

require 'bundler/capistrano'
require 'capistrano/ext/multistage'

set :application, 'spritesheet'
set :user, 'seaneshb'
set :deploy_via, :remote_cache
set :use_sudo, false
set :scm, 'git'
set :repository, 'git@github.com:seaneshbaugh/spritesheet.git'
set :scm_verbose, true
set :bundle_flags, '--deployment'

default_run_options[:pty] = true
ssh_options[:forward_agent] = true

namespace :deploy do
  desc 'No, for real, restart.'
  task :restart_for_real do
    run "touch #{release_path}/tmp/restart.txt"
  end
  after 'deploy:restart', 'deploy:restart_for_real'
end
