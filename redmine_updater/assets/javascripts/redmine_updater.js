$(document).ready(function() {

    show_update_rules('pure_add');
    $("#default_tracker").append("<option value=''></option>");
    check_update_rules();
    
    $("#operation").change(function() {
        show_update_rules($("#operation").val());
    });
    
    $("#default_tracker").change(function() {
        check_update_rules();
    });

    $("#match_submit_button").click(function() {
        $operation =  $("#operation").val();
        $unique_field = $("#unique_field").val();
        default_tracker = $("#default_tracker").val();
        
        if ($operation == 'pure_update') {
            if ($unique_field == "") {
                alert("You must set uniqe-valued colomn!");
                return false;
            }
            
            $("#tracker_field_set_label").hide();
            
        } else if ($operation == 'pure_add') {
            default_tracker = $("#default_tracker").val();
            tracker_field = $("#tracker_field_set").val();
            if ((default_tracker == "") && (tracker_field == "")) {
                alert("You must set tracker field!");
                return false;  
            }
            
        }
    
    });
});


function check_update_rules() {
    default_tracker = $("#default_tracker").val();
    $operation =  $("#operation").val();
    
    if ($operation == "pure_add") {
        if (default_tracker == "") {
            $("#tracker_field_set_label").show();
        } else {
            $("#tracker_field_set_label").hide();
        }
    } else {
        $("#tracker_field_set_label").hide();
    }
}



function show_update_rules(operation) {
    check_update_rules();

    if (operation == "pure_add") {
        $("#match_form").attr("action","/updater/pure_add");
        $("#unique_words_label").hide();
        $("#match_submit_button").removeAttr("disabled");
    } else if (operation == "pure_update") {
        $("#match_form").attr("action","/updater/pure_update");
        $("#unique_words_label").show();
        $("#match_submit_button").removeAttr("disabled");
    } else {
        $("#unique_words_label").hide();
        $("#match_submit_button").attr("disabled","true");
    }
  
}
