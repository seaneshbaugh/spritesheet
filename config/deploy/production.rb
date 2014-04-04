server 'spritesheet.seaneshbaugh.com', :app, :web, :primary => true

set :domain, 'spritesheet.seaneshbaugh.com'
set :branch, 'master'
set :rack_env, 'production'
set :deploy_to, "/home/#{user}/#{application}/#{rack_env}"
