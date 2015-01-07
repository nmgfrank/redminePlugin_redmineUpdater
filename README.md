##redminePlugin_redmineUpdater

This is a redmine plugin which now only support redmine 2.3.2 to redmine 2.3.3.

To deploy this plugin, you should copy ./redmine_updater into plugins folder of redmine.

With this plugin, you can create/update batch of issues from file.

####1. Enable Updater Module

In the page of `Settings->Modules`, check `Batch File Update`.

![image](https://github.com/nmgfrank/redminePlugin_redmineUpdater/blob/master/readme_pic/EnableModule.jpg) 

Then you will see the `Batch File Update` button on the project menu. 

![image](https://github.com/nmgfrank/redminePlugin_redmineUpdater/blob/master/readme_pic/ModuleShow.jpg) 

####2. Create Issues

The main steps of creating issues are generating csv file and import file info the module. 

#####2.1 Generate csv
(1) Edit Excel File

First Line: Titles of data. They should be a one-to-one match between the titles in excel and the field name of redmine ticket.

Other Lines: The data that will be imported. Each line will create a new ticket.

![image](https://github.com/nmgfrank/redminePlugin_redmineUpdater/blob/master/readme_pic/issues_file.jpg) 

*  done_ratio: The value should be integer between 0 to 100
*  assignee: The value should be email address of the user.
*  father-child relationship: It is represented by six `_`.
   If `Task2` is the child of `Task1`, `Task3` is the child of `Task2`, `Task4` is the child of `Task1`, then the excel file should look like below:
<table>
	<tr>
		<th>subject</th>
                  <th>done_ratio</th>
	</tr>
	<tr>
		<td>Task1</td>
		<td></td>
	</tr>
	<tr>
		<td>\_\_\_\_\_\_Task2</td>
		<td>0</td>
	</tr>
	<tr>
		<td>\_\_\_\_\_\_\_\_\_\_\_\_Task3</td>
		<td>10</td>
	</tr>
	<tr>
		<td>\_\_\_\_\_\_Task4</td>
		<td>20</td>
	</tr>
</table>

(2) Save in Format of csv

![image](https://github.com/nmgfrank/redminePlugin_redmineUpdater/blob/master/readme_pic/save_csv.jpg) 

(3) Encode the csv file with utf8

![image](https://github.com/nmgfrank/redminePlugin_redmineUpdater/blob/master/readme_pic/encode_utf8.jpg) 

Now you make the csv!


#####2.2 Load CSV

(1) Choose the csv that you make.
![image](https://github.com/nmgfrank/redminePlugin_redmineUpdater/blob/master/readme_pic/import_index.jpg)

(2) Set import items

* Give a one-to-one match between each title in csv and each field name in redmine ticket.
* Set `add` as the value of `Operation`.
* Set the tracker type that we need as the value of `Default tracker`. If we set this field empty, tracker info must be in the csv file , and be matched to the tracker field in redmine ticket.

![image](https://github.com/nmgfrank/redminePlugin_redmineUpdater/blob/master/readme_pic/import_match.jpg)

(3) Import Exceptions

Data in CSV file will be checked by simple rules. If invalid data exists, error message will appear on the page. You find the error , modify the csv file and import again.  

![image](https://github.com/nmgfrank/redminePlugin_redmineUpdater/blob/master/readme_pic/import_exception.jpg)

(4) Import Result

After importing, result page pops up. The page shows the number of successfully imported items and the number of fails.

![image](https://github.com/nmgfrank/redminePlugin_redmineUpdater/blob/master/readme_pic/import_result.jpg) 


####3 Update Issues

#####3.1 Export Issues
On the bottom of the issues list page, there are the button of export data of issues.

* The field `id` must be exported. It will be the key to update the issue.
* Save the data in the format of `xls` or `xlsx`.

#####3.2 Modify data

Modify the data that you want, such data of `start_date`, `assignee` and so on.

* Never modify the data of `id` column, as it is the key to update. 

#####3.3 Make csv file

Save the modified xls/xlsx file as csv file. Then encode the file as utf8

#####3.4 Load csv, Bulk Update

(1) Choose the csv, then load it.

(2) Set up the updating items.

* Give a one-to-one match to the titles in csv and the field name of redmine tickt.<br /><br />
    Notice:
	+ There must be a match between the title in csv and the `id` field in redmine. When updating, we neet this key to find the issue.
	+ We match the titles those we need except the title of `id`. If the data of certain column is not needed, it should be set as `ignore` .
* Set the value of Operation to `update`.
* If the value of `Default tracker` is set to `Bug`, then only the issues of tracker `Bug` will be updated. If we set the value of `Default tracker` to none, the issues of any tracker could be updated.
* Never leave `Select unique-valued column` empty. We set the value of it to `#`. `#` is the title in csv witch is matched with `id` field in csv.

![image](https://github.com/nmgfrank/redminePlugin_redmineUpdater/blob/master/readme_pic/update_match.jpg) 

(3) Click `Submit`. Start to Update.


































