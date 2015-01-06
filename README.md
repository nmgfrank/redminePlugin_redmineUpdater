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

The main steps of creating issues are generating csv file and import file info the module. There are also two ways to generate csv file: generate csv manually or by vba.

#####2.1 Generate csv manually
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





