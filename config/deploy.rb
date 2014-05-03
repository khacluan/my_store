require 'bundler/capistrano'
require 'capistrano/ext/multistage'
require 'thinking_sphinx/deploy/capistrano'

default_run_options[:pty] = true
set :keep_releases, 5
set :application, "My store"
set :repository,  "git@github.com:RubifyTechnology/hpstar.git"
set :scm, :git
set :rake,  "bundle exec rake"
set :stages, ["staging", "production"]
set :default_stage, "staging"
set :use_sudo,	false
set :deploy_via, :remote_cache
set :rake,  "bundle exec rake"
# if you're still using the script/reaper helper you will need
# these http://github.com/rails/irs_process_scripts

load 'deploy/assets'

after 'deploy:finalize_update', 'deploy:symlink_share', 'deploy:migrate_database', 'sphinx:symlink_indexes'
after "deploy:update", "deploy:cleanup"
# before 'deploy:update_code', 'thinking_sphinx:stop'
# after 'deploy:update_code', 'thinking_sphinx:start'
after  "deploy:restart", "delayed_job:restart"

def remote_file_exists?(full_path)
  'true' ==  capture("if [ -e #{full_path} ]; then echo 'true'; fi").strip
end

namespace :deploy do
  desc "Zero-downtime restart of Unicorn"  
  task :restart, :roles => :web do
    if remote_file_exists?("#{shared_path}/pids/hpstar.pid")
      run "kill -s QUIT `cat #{shared_path}/pids/hpstar.pid`"
    end
    run "cd #{current_path} ; bundle exec unicorn -c config/unicorn.rb -D -E #{rails_env}"
  end
  
  desc "Start unicorn"
  task :start, :except => { :no_release => true } do
    run "cd #{current_path} ; bundle exec unicorn -c config/unicorn.rb -D -E #{rails_env}"
    # run "cd #{current_path}; touch tmp/restart.txt"
  end

  desc "Stop unicorn"
  task :stop, :except => { :no_release => true } do
    run "kill -s QUIT `cat #{shared_path}/pids/hpstar.pid`"
  end  
    
  namespace :assets do
    task :precompile do            
      if !(ENV["SKIP_ASSET"] == "true")        
        run_locally "bundle exec rake assets:precompile RAILS_ENV=#{rails_env}"
        run_locally "cd public; tar -zcvf assets.tar.gz assets"
        top.upload "public/assets.tar.gz", "#{shared_path}", :via => :scp
        run "cd #{shared_path}; tar -zxvf assets.tar.gz"
        run_locally "rm public/assets.tar.gz"
        run_locally "rm -rf public/assets"
        run "rm -rf #{latest_release}/public/assets"
        run "ln -s #{shared_path}/assets #{latest_release}/public/assets"
        run "rm -rf #{shared_path}/assets.tar.gz"
        run "cp #{latest_release}/public/assets/manifest.yml #{latest_release}/assets_manifest.yml"
      end
    end
  end
    
  desc 'migrate database'
  task :migrate_database do
    begin
      run "cd #{release_path} && bundle install --binstubs"
      run "cd #{release_path} && RAILS_ENV=#{rails_env} #{rake} db:migrate"
    rescue => e
    end
  end
      
  desc 'Symlink share'
  task :symlink_share do
    ## Link System folder 
    run "mkdir -p #{shared_path}/system"
    run "ln -nfs #{shared_path}/system #{release_path}/public/system"
    
    ## Link Database file
    run "rm -f #{release_path}/config/database.yml"    
    run "ln -nfs #{shared_path}/config/database.yml #{release_path}/config/database.yml"
    
    ## Copy file to the shared locales folder
    run "mkdir -p #{shared_path}/config/locales"
    run "cp #{release_path}/config/locales/devise.en.yml #{shared_path}/config/locales"
    run "cp #{release_path}/config/locales/dynamic_form.en.yml #{shared_path}/config/locales"
    run "cp #{release_path}/config/locales/en.yml #{shared_path}/config/locales"
    run "cp #{release_path}/config/locales/rubify_dashboard.en.yml #{shared_path}/config/locales"
    ## Remove locales folder and link it back from shared locales
    run "rm -rf #{release_path}/config/locales"
    run "ln -nfs #{shared_path}/config/locales #{release_path}/config/locales"
    
    ## link sale tools folder
    run "mkdir -p #{shared_path}/sale_tools"
    run "rm -rf #{release_path}/public/sale_tools"
    run "ln -nfs #{shared_path}/sale_tools #{release_path}/public/sale_tools"
    
    ## link team commerical folder
    run "mkdir -p #{shared_path}/team_commercial"
    run "rm -rf #{release_path}/public/team_commercial"
    run "ln -nfs #{shared_path}/team_commercial #{release_path}/public/team_commercial"
    
  end
  
  namespace :web do
    desc "Present a maintenance page to visitors."
    task :disable, :roles => :web, :except => { :no_release => true } do
      require 'erb'
      on_rollback { run "rm #{shared_path}/system/maintenance.html" }

      reason = ENV['REASON']
      deadline = ENV['UNTIL']

      template = File.read("./app/views/layouts/maintenance.html.erb")
      result = ERB.new(template).result(binding)

      put result, "#{shared_path}/system/maintenance.html", :mode => 0644
    end
    
    desc "Disable maintenance mode"
    task :enable, :roles => :web do
      run "rm -f #{shared_path}/system/maintenance.html"
    end
  end
end

namespace :sphinx do
  task :symlink_indexes, :roles => [:app] do
    run "mkdir -p #{shared_path}/sphinx"
    run "ln -nfs #{shared_path}/sphinx #{release_path}/db/sphinx"
  end
end

namespace :delayed_job do
  desc "Start delayed_job process"
  task :start do
		p "Starting Delayed Job"
    run "cd #{current_path} && RAILS_ENV=#{rails_env} script/delayed_job start"
  end

  desc "Stop delayed_job process"
  task :stop do
		p "Stopping Delayed Job"
    run "cd #{current_path} && RAILS_ENV=#{rails_env} script/delayed_job stop"
  end

  desc "Restart delayed_job process"
  task :restart do
		p "Restarting Delayed Job"
    run "cd #{current_path} && RAILS_ENV=#{rails_env} script/delayed_job restart"
  end
end