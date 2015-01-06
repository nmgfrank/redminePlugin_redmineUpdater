require_dependency 'issue'

module RedmineUpdaterLib
    module IssuePatch
        def self.included(base)
            base.send(:include, InstanceMethods)
            base.class_eval do 
                attr_accessor :disabled_by_redmine_updater
            end
        end

        module InstanceMethods
 


        end
    end
end

Issue.send(:include, RedmineUpdaterLib::IssuePatch)
