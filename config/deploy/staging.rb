server "192.168.1.102", :app, :web, :db, :primary => true
set :rails_env, "staging"
set :user, 'vu'
set :branch, :master
set :deploy_to, "/home/vu/www/my_store"
# set :port, 3790

default_run_options[:pty] = true
set :default_environment, {
  'PATH' => "/home/vu/.rbenv/shims:/home/vu/.rbenv/bin:$PATH"
}