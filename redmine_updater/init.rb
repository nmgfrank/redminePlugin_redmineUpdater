require 'redmine'

require_dependency 'redmine_updater/issue_patch'
require_dependency 'redmine_updater/journal_patch'


Redmine::Plugin.register :redmine_updater do
  name 'Redmine Updater plugin'
  author 'nmgfrank'
  description 'This is a plugin for Redmine. We can use it to update tasks from csv'
  version '0.0.1'
  author_url 'http://nmgfrankblog.sinaapp.com/'
  
  project_module :updater do
    permission :updater, :updater => :index, :public => true
  end

  menu :project_menu, :updater, { :controller => 'updater', :action => 'index' }, :caption => :label_updater, :before => :settings, :param => :project_id
end
