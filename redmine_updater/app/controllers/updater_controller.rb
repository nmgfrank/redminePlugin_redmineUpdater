require 'csv'
require 'tempfile'

class MultipleIssuesForUniqueValue < Exception
end

class NoIssueForUniqueValue < Exception
end


class UpdaterController < ApplicationController
 
    unloadable
  
    before_filter :find_project
  
    ISSUE_ATTRS = [:id, :subject, :assigned_to, :fixed_version,
    :author, :description, :category, :priority, :tracker, :status,
    :start_date, :due_date, :done_ratio, :estimated_hours,
    :parent_issue, :watchers ]
    
    def index
    end

    def wrong_csv
        @project_id = @project.id
        @error = params['error']
    end
  
    def match
        
        # Delete existing iip to ensure there can't be two iips for a user
        UpdateInProgresses.delete_all(["user_id = ?",User.current.id])
     
        # save import-in-progress data
        iip = UpdateInProgresses.find_or_create_by_user_id(User.current.id)
        iip.quote_char = params[:wrapper]
        iip.col_sep = params[:splitter]
        iip.encoding = params[:encoding]
        iip.created = Time.new
        iip.csv_data = params[:file].read
        iip.save
     
        
        # Put the timestamp in the params to detect
        # users with two imports in progress
        @import_timestamp = iip.created.strftime("%Y-%m-%d %H:%M:%S")
        @original_filename = params[:file].original_filename
        
        # display sample
        sample_count = 5
        i = 0
        @samples = []
        
        begin
            CSV.new(iip.csv_data, {:headers=>true,
                                   :encoding=>iip.encoding,
                                   :quote_char=>iip.quote_char,
                                   :col_sep=>iip.col_sep}).each do |row|
            
                @samples[i] = row
                i += 1
                if i >= sample_count
                    break
                end
            end # do
        rescue => err
           redirect_to(:action=>'wrong_csv',:project_id => params[:project_id], :error => err.to_s)
           return
        end            


        if @samples.size > 0
          @headers = @samples[0].headers
        end

        @headers.each do |header|
            if header.nil?
                redirect_to(:action=>'wrong_csv',:project_id => params[:project_id], :error => "there are nil value in headers :" + @headers.to_s)
                return
            end
        end
       
        # fields
        @attrs = Array.new
        ISSUE_ATTRS.each do |attr|
          #@attrs.push([l_has_string?("field_#{attr}".to_sym) ? l("field_#{attr}".to_sym) : attr.to_s.humanize, attr])
          @attrs.push([l_or_humanize(attr, :prefix=>"field_"), attr])
        end
        @project.all_issue_custom_fields.each do |cfield|
          @attrs.push([cfield.name, cfield.name])
        end
        IssueRelation::TYPES.each_pair do |rtype, rinfo|
          @attrs.push([l_or_humanize(rinfo[:name]),rtype])
        end
        @attrs.sort_by{|u| u[0]}
   
    end
  
  
    def pure_add
        _general_log('plugin: redmine_updater', 'pure_add')
        @handle_count = 0 # the num of records in csv
        @update_count = 0 # the num of records those were saved successfully
        @skip_count = 0 # the num of records whose were skipped, so such records are not processed
        @failed_count = 0 # the num of records those fails to be saved 
        @failed_issues = Hash.new # the Hash stores the records those fails to be saved
        @affect_projects_issues = Hash.new # ???????????????????????????
        # This is a cache of previously inserted issues indexed by the value
        # the user provided in the unique column
        @issue_by_unique_attr = Hash.new
        # Cache of user id by login
        @user_by_login = Hash.new
        # Cache of Version by name
        @version_id_by_name = Hash.new
        
        # Retrieve saved import data
        iip = UpdateInProgresses.find_by_user_id(User.current.id)
        if iip == nil
          flash[:error] = "No import is currently in progress(no proper data in database)."
          return
        end
        if iip.created.strftime("%Y-%m-%d %H:%M:%S") != params[:import_timestamp]
          flash[:error] = "You seem to have started another import " \
              "since starting this one. " \
              "This import cannot be completed"
          return
        end

        # key is the title in csv,  while value is the title in redmine 
        fields_map = {}
        params[:fields_map].each { |k, v| fields_map[k.unpack('U*').pack('U*')] = v }
        # attrs_map is fields_map's invert.
        # the key is title in redmine, while value is in csv.
        attrs_map = fields_map.invert
        # check params ????????????????

        add_versions = params[:add_versions]
        add_categories = params[:add_categories]
        default_tracker_id = params[:default_tracker]
        tracker_field_set = params[:tracker_field_set]
        
        
        if default_tracker_id.blank?
            if tracker_field_set.nil? || !(fields_map.has_key? tracker_field_set)
                flash[:error] = "Defalut Tracker Is Empty and Tracker Field Is Not Specified. "  
                return  
            end
            tracker_redmine_field = fields_map[tracker_field_set] 
        end

        users_hash = {}
        users_email_hash = {}
        @project.users.each do |user|
            user_id = user.id
            username = (user.lastname + user.firstname).split.join('').to_s
            users_hash[username.downcase] = user_id
            users_email_hash[user.mail.downcase] = user_id
        end
        
       
        # pre-check: check before save
        row_cnt = 0
        @header_index_hash = Hash.new # key is title in csv, value is index which is start from 0.
        @parent_id_list = []
        
        CSV.new(iip.csv_data, {:headers=>true,
                           :encoding=>iip.encoding,
                           :quote_char=>iip.quote_char,
                           :col_sep=>iip.col_sep}).each do |row| 

            row.each do |k, v|
                k = k.unpack('U*').pack('U*') if k.kind_of?(String) && k.blank?
                v = v.unpack('U*').pack('U*') if v.kind_of?(String) && v.blank?
                row[k] = v.nil? ? "" : v.force_encoding("utf-8")
            end 
            # row : key is title in csv, value is the detail value in csv
            if row_cnt <= 0
                headers = row.headers
                inner_cnt = 0
                headers.each do |header|
                   @header_index_hash[header.unpack('U*').pack('U*')] = inner_cnt
                   inner_cnt =inner_cnt + 1
                end
            end
            
            # check status
            status = IssueStatus.find_by_name(row[@header_index_hash[attrs_map["status"]]])
            if row[@header_index_hash[attrs_map["status"]]].present? && status.blank?
                flash[:error] = "\nWrong Status : #{row[@header_index_hash[attrs_map["status"]]]}. \n Line #{row_cnt + 1}: "  + row.to_s
                return
            
            end
            
            # check subject and father & children logic
            if row[@header_index_hash[attrs_map["subject"]]].blank?
                flash[:error] = "\nSubject Should Not Be Empty. \n Line #{row_cnt + 1}: "  + row.to_s
                return
            else 
                subject = row[@header_index_hash[attrs_map["subject"]]].strip
                current_level = _get_current_subject_level subject
                
                last_level = @parent_id_list.length
                
                if last_level < current_level - 1
                    flash[:error] = "Parent And Child Error! Child is Too Deep For Its Father. \n Line #{row_cnt + 1}: "  + row.to_s
                    return
                elsif last_level == current_level - 1
                    @parent_id_list.push(1)
                elsif last_level == current_level
                    
                else
                    less_num =  last_level - current_level 
                    if @parent_id_list.length - less_num > 0
                        (1..less_num).each do |idx|
                            @parent_id_list.pop
                        end    
                    end
                    
                    if @parent_id_list.length <= 0
                        flash[:error] = "Logic Error. Can not be here logically.@parent_id_list == 0"
                        return
                    end  
                end
            end
            
              
            # check date
            begin
                state_date = row[@header_index_hash[attrs_map["start_date"]]].blank? ? nil : Date.parse(row[@header_index_hash[attrs_map["start_date"]]])
            rescue
                flash[:error] = "\nStart Date Format Error. \nLine #{row_cnt + 1}: "  + row.to_s
                return
            end
            
            begin
                end_date = row[@header_index_hash[attrs_map["due_date"]]].blank? ? nil : Date.parse(row[@header_index_hash[attrs_map["due_date"]]])
            rescue
                flash[:error] = "\nEnd Date Format Error. \nLine #{row_cnt + 1}: "  + row.to_s
                return           
            end
            
            if (!state_date.nil? && !end_date.nil?) && (end_date - state_date).days < 0
                flash[:error] = "\nEnd Date is Behide Start Date. \nLine #{row_cnt + 1}: "  + row.to_s
                return  
            end
            
            
            # check assigned user 
            assigned_username = ""
            if !attrs_map["assigned_to"].blank?
                assigned_username = row[@header_index_hash[attrs_map["assigned_to"]]].to_s.split.join('').to_s
            end
            
            if !assigned_username.blank?
                if users_email_hash.has_key? assigned_username.downcase
                    
                elsif users_hash.has_key? assigned_username
                    
                else
                    assigned_user_id = nil
                    flash[:error] = "\nThe assigned user #{assigned_username} is not member of project \nLine #{row_cnt + 1}: "  + row.to_s
                    return 
                end   
            end 
             
            tmp_issue = Issue.new
            tmp_issue.project_id = @project.id
            # check relation
            IssueRelation::TYPES.each_pair do |rtype, rinfo|
                if row[@header_index_hash[attrs_map[rtype]]].blank?
                    next
                end
                
                content = row[@header_index_hash[attrs_map[rtype]]]
                if content.blank?
                    next
                end
                
                ids_array = content.split ","
                ids_array.each do |issue_id|
                    other_issue = Issue.find_by_id(issue_id) 
                    if other_issue.nil?
                        flash[:error] = "\nThe related issue (id: #{issue_id}) is not exists! \nLine #{row_cnt + 1}: "  + row.to_s
                        return  
                    end
                end
            
            end
                   
            
            row_cnt =row_cnt + 1
        end  
        
           
        
        # start to save
        row_cnt = 0    
        @parent_id_list = []      
        CSV.new(iip.csv_data, {:headers=>true,
                           :encoding=>iip.encoding,
                           :quote_char=>iip.quote_char,
                           :col_sep=>iip.col_sep}).each do |row| 

            row.each do |k, v|
                k = k.unpack('U*').pack('U*') if k.kind_of?(String) && k.blank?
                v = v.unpack('U*').pack('U*') if v.kind_of?(String) && v.blank?
                row[k] = v.nil? ? "" : v.force_encoding("utf-8")
            end 
            # row : key is title in csv, value is the detail value in csv
            @handle_count += 1
            if row_cnt <= 0
                headers = row.headers
                inner_cnt = 0
                headers.each do |header|
                   @header_index_hash[header.unpack('U*').pack('U*')] = inner_cnt
                   inner_cnt =inner_cnt + 1
                end
            end
            row_cnt =row_cnt + 1
       
            
            
            # create new issue
            issue = Issue.new
            issue.disabled_by_redmine_updater = true
        
            begin  
                
                #project = Project.find_by_name(row[attrs_map["project"]])
                #if !project
                #  project = @project
                #end
                project = @project
                # ignore tracker, it is indicated by default_tracker_id   
                # tracker = Tracker.find_by_name(@header_index_hash[row[attrs_map["tracker"]]])
                
                
                status = IssueStatus.find_by_name(row[@header_index_hash[attrs_map["status"]]])
                priority = Enumeration.find_by_name(row[attrs_map["priority"]])
                fixed_version_name = row[@header_index_hash[attrs_map["fixed_version"]]].blank? ? nil : row[@header_index_hash[attrs_map["fixed_version"]]]
                fixed_version_id = fixed_version_name ? version_id_for_name!(project,fixed_version_name,add_versions) : nil  

                assigned_username = ""
                if !attrs_map["assigned_to"].blank?
                    assigned_username = row[@header_index_hash[attrs_map["assigned_to"]]].to_s.split.join('').to_s
                end
                 
                if users_email_hash.has_key? assigned_username.downcase
                    assigned_user_id = users_email_hash[assigned_username.downcase]
                elsif users_hash.has_key? assigned_username
                    assigned_user_id = users_hash[assigned_username.downcase] 
                else
                    assigned_user_id = nil
                end


            rescue ActiveRecord::RecordNotFound
                @failed_issues[@failed_count] = row
                @failed_count += 1
                row['fails reason'] = "record not found because of version"

                logger.info "When updating issue #{@failed_count} below, the #{@unfound_class} #{@unfound_key} was not found"
                next          
            end
            
            begin
                if !default_tracker_id.blank?
                    tracker_id = default_tracker_id  
                else
                    tracker_name = row[@header_index_hash[attrs_map[tracker_redmine_field]]]

                    trackers = Tracker.where(["name = ?", tracker_name])

                    
                    if !trackers.blank?
                        tracker = trackers[0]
                        tracker_id = tracker.id
                    else
                        raise 
                    end

                end
            
            rescue
                @failed_issues[@failed_count] = row
                @failed_count += 1
                row['fails reason'] = "Can not find proper tracker! Row:  " + row.to_s

                logger.info "When updating issue #{@failed_count} below, the #{@unfound_class} #{@unfound_key} was not found"
                next        
            end
            

            begin  
                category_name = row[attrs_map["category"]]
                category = IssueCategory.find_by_project_id_and_name(project.id, category_name)
                if (!category) && category_name && category_name.length > 0 && add_categories
                    category = project.issue_categories.build(:name => category_name)
                    category.save
                end
            rescue ActiveRecord::RecordNotFound
                category = nil
            end

            # set value for new issue
            issue.fixed_version_id = fixed_version_id != nil
            issue.project_id = project != nil ? project.id : @project.id
            
            
            issue.tracker_id = tracker_id.blank? ? issue.tracker_id : tracker_id
            
            
            issue.author_id = User.current.id
            issue.fixed_version_id = fixed_version_id != nil ? fixed_version_id : issue.fixed_version_id
            
            # set value for required attributes
            issue.status_id = status != nil ? status.id : issue.status_id
            issue.priority_id = priority != nil ? priority.id : issue.priority_id
            subject = row[@header_index_hash[attrs_map["subject"]]] || issue.subject
            issue.subject = _get_current_subject subject
            
            # parent_issue_id
            current_level = _get_current_subject_level subject
            if current_level > 1
                if @parent_id_list.length >= current_level - 1
                    issue.parent_issue_id = @parent_id_list[current_level - 2]
                else
                    flash[:error] = "\nLogic Error. @parent_id_list is shorter than needed\nLine #{row_cnt + 1}: "  + row.to_s + "\n @parent_id_list: " + @parent_id_list.to_s
                    return                      
                end
            end
            
 
            # optional attributes
            issue.assigned_to_id  = assigned_user_id.nil? ? issue.assigned_to_id : assigned_user_id
            issue.description = row[@header_index_hash[attrs_map["description"]]] || issue.description
            issue.category_id = category != nil ? category.id : issue.category_id
            
            begin
                issue.start_date = row[@header_index_hash[attrs_map["start_date"]]].blank? ? nil : Date.parse(row[@header_index_hash[attrs_map["start_date"]]])            
            rescue
                @failed_issues[@failed_count] = row
                @failed_count += 1
                row['fails reason'] = "Start Date Parse Error. "
                next   
            end
            
            begin
                issue.due_date = row[@header_index_hash[attrs_map["due_date"]]].blank? ? nil : Date.parse(row[@header_index_hash[attrs_map["due_date"]]])            
            rescue
                @failed_issues[@failed_count] = row
                @failed_count += 1
                row['fails reason'] = "End Date Parse Error. "
                next             
            end

            issue.fixed_version_id = fixed_version_id != nil ? fixed_version_id : issue.fixed_version_id
            issue.done_ratio = row[@header_index_hash[attrs_map["done_ratio"]]].blank? ? issue.done_ratio : row[@header_index_hash[attrs_map["done_ratio"]]]
            
            
            issue.estimated_hours = row[@header_index_hash[attrs_map["estimated_hours"]]] || issue.estimated_hours
            
            # custom fields
            custom_failed_count = 0
            h = {}
            issue.available_custom_fields.each do |cf|
                if value = row[@header_index_hash[attrs_map[cf.name]]]
                    begin
                        if cf.field_format == 'user'
                          value = user_id_for_login!(value).to_s
                        elsif cf.field_format == 'version'
                          value = version_id_for_name!(project,value,add_versions).to_s
                        elsif cf.field_format == 'date'
                          value = value.to_date.to_s(:db)
                        end
                        h[cf.id] = value
                    rescue
                        logger.info "When trying to set custom field #{cf.name} on issue #{@failed_count} below, value #{value} was invalid"
                    end
                end  
            end

            issue.custom_field_values = h

            # save
            unless issue.save
                logger.info "Error occurs while saving, for the value {#{row}} were found"
                @failed_count += 1
                @failed_issues[@failed_count] = row


                error_msg = ""
                issue.errors.each do |attr, error_message|
                    error_msg += attr.to_s + ",  " + error_message + " ;"
                end

                row['fails reason'] = "fails while saving at last step:  " + error_msg
            else

                # parrent issue level list
                subject = row[@header_index_hash[attrs_map["subject"]]] || issue.subject
                current_level = _get_current_subject_level subject
                last_level = @parent_id_list.length
                
                if last_level < current_level - 1
                    flash[:error] = "Parent And Child Error! Child is Too Deep For Its Father. \n Line #{row_cnt + 1}: "  + row.to_s
                    return
                elsif last_level == current_level - 1
                    @parent_id_list.push(issue.id)
                elsif last_level == current_level
                    @parent_id_list.pop
                    @parent_id_list.push(issue.id)    
                else
                    less_num =  last_level - current_level 
                    if @parent_id_list.length - less_num > 0
                        (0..less_num).each do |idx|
                            @parent_id_list.pop
                        end  
                        @parent_id_list.push(issue.id)   
                    end
                    
                    if @parent_id_list.length <= 0
                        flash[:error] = "Logic Error. Can not be here logically.@parent_id_list == 0"
                        return
                    end  
                end                  



                # relationship
                IssueRelation::TYPES.each_pair do |rtype, rinfo|
                    if row[@header_index_hash[attrs_map[rtype]]].blank?
                        next
                    end
                    content = row[@header_index_hash[attrs_map[rtype]]]
                    if content.blank?
                        next
                    end
                    
                    ids_array = content.split ","
                    ids_array.each do |issue_id|
                        other_issue = Issue.find_by_id(issue_id) 
                        if other_issue.nil?
                            flash[:error] = "\nThe related issue (id: #{issue_id}) is not exists! \nLine #{row_cnt + 1}: "  + row.to_s
                            return  
                        end

                        relation = IssueRelation.new( :issue_from => issue, :issue_to => other_issue, :relation_type => rtype )
                        relation.save
                        
                    end
                end














                @update_count += 1 
            end

        end
        if @failed_issues.size > 0
          @failed_issues = @failed_issues.sort
          @headers = @failed_issues[0][1].headers
        end
        # Clean up after ourselves
        iip.delete
        
        # Garbage prevention: clean up iips older than 3 days
        UpdateInProgresses.delete_all(["created < ?",Time.new - 3*24*60*60])

    end

  
    def pure_update
        _general_log('plugin: redmine_updater', 'pure_update')
        @handle_count = 0 # the num of records in csv
        @update_count = 0 # the num of records those were saved successfully
        @skip_count = 0 # the num of records whose were skipped, so such records are not processed
        @failed_count = 0 # the num of records those fails to be saved 
        @failed_issues = Hash.new # the Hash stores the records those fails to be saved
        @affect_projects_issues = Hash.new # ???????????????????????????
        # This is a cache of previously inserted issues indexed by the value
        # the user provided in the unique column
        @issue_by_unique_attr = Hash.new
        # Cache of user id by login
        @user_by_login = Hash.new
        # Cache of Version by name
        @version_id_by_name = Hash.new
        
        # Retrieve saved import data
        iip = UpdateInProgresses.find_by_user_id(User.current.id)
        if iip == nil
          flash[:error] = "No import is currently in progress(no proper data in database)."
          return
        end
        if iip.created.strftime("%Y-%m-%d %H:%M:%S") != params[:import_timestamp]
          flash[:error] = "You seem to have started another import " \
              "since starting this one. " \
              "This import cannot be completed"
          return
        end

        # key is the title in csv,  while value is the title in redmine 
        fields_map = {}
        params[:fields_map].each { |k, v| fields_map[k.unpack('U*').pack('U*')] = v }
        # attrs_map is fields_map's invert.
        # the key is title in redmine, while value is in csv.
        attrs_map = fields_map.invert
        # check params ????????????????
        
        uniqu_field_csv_title = params[:unique_field]
        uniqu_field_redmine_title = fields_map[uniqu_field_csv_title]
        
        if !(["subject","id"].include? uniqu_field_redmine_title.strip )
            flash[:error] = "Unique colomn value should only be subject or id; If you need other unique colomn, please contact administrator. "  
            return  
        end

        add_versions = params[:add_versions]
        add_categories = params[:add_categories]
        default_tracker_id = params[:default_tracker]
        

        
        users_hash = {}
        user_mails_hash = {}
        @project.users.each do |user|
            user_id = user.id
            username = (user.lastname + user.firstname).split.join('').to_s
            users_hash[username.strip.downcase] = user_id
            user_mails_hash[user.mail.strip.downcase] = user_id
        end


        # pre-check: check before save
        row_cnt = 0
        @header_index_hash = Hash.new # key is title in csv, value is index which is start from 0.
        @parent_id_list = []
        
        CSV.new(iip.csv_data, {:headers=>true,
                           :encoding=>iip.encoding,
                           :quote_char=>iip.quote_char,
                           :col_sep=>iip.col_sep}).each do |row| 

            row.each do |k, v|
                k = k.unpack('U*').pack('U*') if k.kind_of?(String) && k.blank?
                v = v.unpack('U*').pack('U*') if v.kind_of?(String) && v.blank?
                row[k] = v.nil? ? "" : v.force_encoding("utf-8")
            end 
            # row : key is title in csv, value is the detail value in csv
            if row_cnt <= 0
                headers = row.headers
                inner_cnt = 0
                headers.each do |header|
                   @header_index_hash[header.unpack('U*').pack('U*')] = inner_cnt
                   inner_cnt =inner_cnt + 1
                end
            end
            
            #check status when update
            _status_value = row[@header_index_hash[attrs_map["status"]]];
            @_status = IssueStatus.find_by_sql ["SELECT * FROM issue_statuses WHERE name = ? ", _status_value];
            if @_status.blank?
                flash[:error] = "\nStatus Format Error. \nLine #{row_cnt + 1}: "  + row.to_s
                return;
            
            end
              
            # check date
            begin
                state_date = row[@header_index_hash[attrs_map["start_date"]]].blank? ? nil : Date.parse(row[@header_index_hash[attrs_map["start_date"]]])
            rescue
                flash[:error] = "\nStart Date Format Error. \nLine #{row_cnt + 1}: "  + row.to_s
                return
            end
            
            begin
                end_date = row[@header_index_hash[attrs_map["due_date"]]].blank? ? nil : Date.parse(row[@header_index_hash[attrs_map["due_date"]]])
            rescue
                flash[:error] = "\nEnd Date Format Error. \nLine #{row_cnt + 1}: "  + row.to_s
                return           
            end
            
            if (!state_date.nil? && !end_date.nil?) && (end_date - state_date).days < 0
                flash[:error] = "\nEnd Date is Behide Start Date. \nLine #{row_cnt + 1}: "  + row.to_s
                return  
            end
            
            
            # check assigned user 
            assigned_username = ""
            if !attrs_map["assigned_to"].blank?
                assigned_username = row[@header_index_hash[attrs_map["assigned_to"]]].to_s.split.join('').to_s.strip.downcase
            end
            
            if !assigned_username.blank?
                if user_mails_hash.has_key? assigned_username
                    
                elsif users_hash.has_key? assigned_username
                    
                else
                    assigned_user_id = nil
                    flash[:error] = "\nThe assigned user #{assigned_username} is not member of project \nLine #{row_cnt + 1}: "  + row.to_s
                    return 
                end   
            end         
            
            row_cnt =row_cnt + 1
        end  
        
           


        
        # after check, start to update 
        row_cnt = 0
        @header_index_hash = Hash.new # key is title in csv, value is index which is start from 0.
        CSV.new(iip.csv_data, {:headers=>true,
                           :encoding=>iip.encoding,
                           :quote_char=>iip.quote_char,
                           :col_sep=>iip.col_sep}).each do |row| 
          

            row.each do |k, v|
                k = k.unpack('U*').pack('U*') if k.kind_of?(String) && k.blank?
                v = v.unpack('U*').pack('U*') if v.kind_of?(String) && v.blank?
                row[k] = v.nil? ? "" : v.force_encoding("utf-8")
             
            end 
            # row : key is title in csv, value is the detail value in csv
            @handle_count += 1
            if row_cnt <= 0
                headers = row.headers
                inner_cnt = 0
                headers.each do |header|
                   @header_index_hash[header.unpack('U*').pack('U*')] = inner_cnt
                   inner_cnt =inner_cnt + 1
                end
            end
            row_cnt =row_cnt + 1

            # get issue that need to be update
            _status_value = row[@header_index_hash[attrs_map["status"]]];
            @_status = IssueStatus.find_by_sql ["SELECT * FROM issue_statuses WHERE name = ? ", _status_value];
            _status_id=0;
            for record in @_status
                _status_id = record.id;
            end
            

            begin 
                uniqu_field_value = row[@header_index_hash[attrs_map[uniqu_field_redmine_title]]]
                
                issue = issue_for_unique_attr(uniqu_field_redmine_title,uniqu_field_value,row)
                issue.status_id = _status_id;
                
                
                issue.init_journal(User.current, "Update By System!")
                issue.current_journal.disabled_by_redmine_updater = true
            
            rescue NoIssueForUniqueValue
                @failed_count += 1
                @failed_issues[@failed_count] = row

                row['fails reason'] = "NoIssueForUniqueValue: unique_field" + uniqu_field_redmine_title + ", value " + uniqu_field_value
                next
            rescue MultipleIssuesForUniqueValue
                @failed_count += 1
                @failed_issues[@failed_count] = row

                row['fails reason'] = "MultipleIssuesForUniqueValue: unique_field" + uniqu_field_redmine_title + ", value " + uniqu_field_value
                next   
            end
            
            if !default_tracker_id.blank?
                if issue.tracker_id.to_s != default_tracker_id.to_s
                    @failed_count += 1
                    @failed_issues[@failed_count] = row

                    row['fails reason'] = "Tracker id is not right. The tracker id in redmine is #{issue.tracker_id} while in csv is #{default_tracker_id}"
                    next
                end
            end
            
            begin
                #project = Project.find_by_name(row[attrs_map["project"]])
                #if !project
                #  project = @project
                #end
                project = @project
                # ignore tracker, it is indicated by default_tracker_id   
                # tracker = Tracker.find_by_name(@header_index_hash[row[attrs_map["tracker"]]])
                status = IssueStatus.find_by_name(row[attrs_map["status"]])
                priority = Enumeration.find_by_name(row[attrs_map["priority"]])
                fixed_version_name = row[@header_index_hash[attrs_map["fixed_version"]]].blank? ? nil : row[@header_index_hash[attrs_map["fixed_version"]]]
                fixed_version_id = fixed_version_name ? version_id_for_name!(project,fixed_version_name,add_versions) : nil  

                assigned_username = ""
                if !attrs_map["assigned_to"].blank?
                    assigned_username = row[@header_index_hash[attrs_map["assigned_to"]]].to_s.split.join('').to_s.downcase
                end
                
                if users_hash.has_key? assigned_username
                    assigned_user_id = users_hash[assigned_username]
                elsif user_mails_hash.has_key? assigned_username
                    assigned_user_id = user_mails_hash[assigned_username]
                else
                    assigned_user_id = nil
                end

            rescue ActiveRecord::RecordNotFound
                @failed_issues[@failed_count] = row
                @failed_count += 1
                row['fails reason'] = "record not found because of version"

                logger.info "When updating issue #{@failed_count} below, the #{@unfound_class} #{@unfound_key} was not found"
                next          
            end



            begin  
                category_name = row[attrs_map["category"]]
                category = IssueCategory.find_by_project_id_and_name(project.id, category_name)
                if (!category) && category_name && category_name.length > 0 && add_categories
                    category = project.issue_categories.build(:name => category_name)
                    category.save
                end
            rescue ActiveRecord::RecordNotFound
                category = nil
            end

            # set value for new issue
            # It is not necessary to change project
            #issue.project_id = project != nil ? project.id : @project.id
            
            

            # set value for required attributes
            if attrs_map.has_key? "status"
                issue.status_id = status != nil ? status.id : issue.status_id
            end
            
            if attrs_map.has_key? "priority"
                issue.priority_id = priority != nil ? priority.id : issue.priority_id
            end
            
            if attrs_map.has_key? "subject"
                issue.subject = row[@header_index_hash[attrs_map["subject"]]] || issue.subject
            end
 
            # optional attributes
            if attrs_map.has_key? "assigned_to"
                issue.assigned_to_id  = assigned_user_id.blank? ? issue.assigned_to_id : assigned_user_id
            end
            
            if attrs_map.has_key? "description"
                issue.description = row[@header_index_hash[attrs_map["description"]]] || issue.description
            end
            
            if attrs_map.has_key? "category"
                issue.category_id = category != nil ? category.id : issue.category_id
            end
            
            if attrs_map.has_key? "start_date"
                issue.start_date = row[@header_index_hash[attrs_map["start_date"]]].blank? ? nil : Date.parse(row[@header_index_hash[attrs_map["start_date"]]])
            end
            
            if attrs_map.has_key? "due_date"
                issue.due_date = row[@header_index_hash[attrs_map["due_date"]]].blank? ? nil : Date.parse(row[@header_index_hash[attrs_map["due_date"]]])
            end

            if attrs_map.has_key? "fixed_version"
                issue.fixed_version_id = !fixed_version_id.blank? ? fixed_version_id : issue.fixed_version_id
            end
     
            if attrs_map.has_key? "done_ratio"
                issue.done_ratio = row[@header_index_hash[attrs_map["done_ratio"]]] || issue.done_ratio
            end
            
            if attrs_map.has_key? "estimated_hours"
                issue.estimated_hours = row[@header_index_hash[attrs_map["estimated_hours"]]] || issue.estimated_hours
            end

            # custom fields
            custom_failed_count = 0
            h = {}
            issue.available_custom_fields.each do |cf|
                if value = row[@header_index_hash[attrs_map[cf.name]]]
                    begin
                        if cf.field_format == 'user'
                          value = user_id_for_login!(value).to_s
                        elsif cf.field_format == 'version'
                          value = version_id_for_name!(project,value,add_versions).to_s
                        elsif cf.field_format == 'date'
                          value = value.to_date.to_s(:db)
                        end
                        h[cf.id] = value
                    rescue
                        logger.info "When trying to set custom field #{cf.name} on issue #{@failed_count} below, value #{value} was invalid"
                    end
                end  
            end

            issue.custom_field_values = h
            
            


            # save
            unless issue.save
                logger.info "Error occurs while saving, for the value {#{row}} were found"
                @failed_count += 1
                @failed_issues[@failed_count] = row


                error_msg = ""
                issue.errors.each do |attr, error_message|
                    error_msg += attr.to_s + ",  " + error_message + " ;"
                end

                row['fails reason'] = "fails while saving at last step:  " + error_msg

            else
                logger.info "success to save #{row}"
                
                @update_count += 1 
            end

        end
        if @failed_issues.size > 0
          @failed_issues = @failed_issues.sort
          @headers = @failed_issues[0][1].headers
        end
        # Clean up after ourselves
        iip.delete
        
        # Garbage prevention: clean up iips older than 3 days
        UpdateInProgresses.delete_all(["created < ?",Time.new - 3*24*60*60])

    end






    # Returns the id for the given version or raises RecordNotFound.
    # Implements a cache of version ids based on version name
    # If add_versions is true and a valid name is given,
    # will create a new version and save it when it doesn't exist yet.
    def version_id_for_name!(project,name,add_versions)
    
       
      if !@version_id_by_name.has_key?(name)
        version = Version.find_by_project_id_and_name(project.id, name)
        if !version
          if name && (name.length > 0) && add_versions
            version = project.versions.build(:name=>name)
            version.save
          else
            @unfound_class = "Version"
            @unfound_key = name
            raise ActiveRecord::RecordNotFound, "No version named #{name}"
          end
        end
        @version_id_by_name[name] = version.id
      end
      @version_id_by_name[name]
    end
  
  
    def issue_for_unique_attr(unique_attr, attr_value, row_data)
  
      if unique_attr == "id"
        issues = [Issue.find_by_id(attr_value)]
        
      else
        sql_where = " #{unique_attr} = '#{attr_value}' and project_id = #{@project.id} "
        issues = Issue.where([sql_where]).limit(2)
 
      end
      
      if issues.size > 1
          raise MultipleIssuesForUniqueValue
      else
        if issues.size == 0
          raise NoIssueForUniqueValue
        end
        if issues.first.blank?
            raise NoIssueForUniqueValue
        else
            return issues.first
        end
      end
    end
 

    def user_id_for_login!(login)
        user = user_for_login!(login)
        user ? user.id : nil
    end
    
    
    
    # Returns the id for the given user or raises RecordNotFound
    # Implements a cache of users based on login name
    def user_for_login!(login)
        begin
          if !@user_by_login.has_key?(login)
            @user_by_login[login] = User.find_by_login!(login)
          end
          @user_by_login[login]
        rescue ActiveRecord::RecordNotFound
       
          raise
        end
    end
    





  
  private
  
        def find_project
          @project = Project.find(params[:project_id])
        end
        
        def flash_message(type, text)
          flash[type] ||= ""
          flash[type] += "#{text}<br/>"
        end

        def _general_log(module_name, operation_name, args_list = [])
            args_str = ''
            args_list.each do |arg|
                args_str += arg.to_s + ','
            end
            Rails.logger.info 'SystemAnalyze;' + Time.now.strftime("%Y-%m-%d %H:%M:%S").to_s + ';' + (User.current.blank? ? 'blank': User.current.to_s) + ';' + module_name.to_s + ";" +operation_name.to_s + ';' + args_str  
    
        end    
  
 
        def _get_current_subject_level subject
            prifix_num = 0
            subject.each_char() {|c|  
                if c == "_"
                    prifix_num += 1 
                else 
                    break
                end 
            }
            
            if prifix_num % 6 != 0
                flash[:error] = "\nInvalid Subject Name. The Prefix should be a multiple of 6. \n Line #{row_cnt + 1}: "  + row.to_s
                return
            end
            
            current_level = (prifix_num / 6).to_i + 1        
        end 
  
  
        def _get_current_subject subject
            prifix_num = 0
            subject.each_char() {|c|  
                if c == "_"
                    prifix_num += 1 
                else 
                    break
                end 
            }
            
            
            return subject[prifix_num, subject.length]   
        end   
  
   
    
end
