require_dependency 'journal'

module RedmineUpdaterLib
    module JournalPatch
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

Journal.send(:include, RedmineUpdaterLib::JournalPatch)
