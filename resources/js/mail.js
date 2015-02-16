/**
 * @author (c) MLstate, 2011-2014
 */

// auto-activate navbar items and list-group items
function auto_activate() {
    // sidebar
    $('.list-unstyled dt').click(function () {
        $(this).addClass('active').siblings().removeClass('active');
    });
    // file items
    $('.list-group-item').on('click', function(e) {
        var previous = $(this).closest('.list-group').children('.active');
        previous.removeClass('active');
        $(e.target).addClass('active');
    });
}

function split(val) {
    return val.split(/,\s*/);
}

function extractLast(term) {
    return split(term).pop();
}

function belongs(val, records) {
    var res = false;
    for (r in records) {
	res = res || (records[r] === val);
    }
    return res;
}

function label_renderer(ul, item) {
    return $("<li></li>")
	.data("item.autocomplete", item)
	.append("<a title='"
		+ $('<span/>').text(item.icon).html().replace("\'", "&#39;")
		+ $('<span/>').text(item.title).html().replace("\'", "&#39;")
		//+ " [" + $('<span/>').text(item.cat).html() + "]"
		+ "' rel='popover' "
                + "data-placement='left' "
                + "data-content='"
		+ $('<br/>').html()
		+ $('<div/>').text(item.desc).html().replace("\'", "&#39;")
		+ "'>"
		+ item.icon
                + item.label
                + "</a>")
	.appendTo(ul);
}

function file_renderer(ul, item) {
    return $("<li></li>")
	.data("item.autocomplete", item)
	.append("<a title='"
		+ $('<span/>').text(item.icon).html().replace("\'", "&#39;")
		+ $('<span/>').text(item.title).html().replace("\'", "&#39;")
		//+ " [" + $('<span/>').text(item.cat).html() + "]"
		+ "' rel='popover' "
                + "data-placement='left' "
                + "data-content='"
		+ $('<br/>').html()
		+ $('<div/>').text(item.desc).html().replace("\'", "&#39;")
		+ "'>"
		+ item.icon
                + item.file
                + "</a>")
	.appendTo(ul);
}

function blur(e) {
  //setTimeout("$(this).autocomplete('close')", 1000);
    $(this).autocomplete('close');
}

function init_autocomplete(input) {
    $(input)
    // don't navigate away from the field on tab when selecting an item
    .bind("keydown", function(event) {
        if (event.keyCode === $.ui.keyCode.TAB &&
            $(this).data("autocomplete") &&
            $(this).data("autocomplete").menu.active) {
            event.preventDefault();
        }
    })
    .autocomplete({
        minLength: 0,
        source: function(request, response) {
            console.log("to_input");
            $.getJSON("/_user/addresses", {
                term: extractLast(request.term)
            }, response);
        },
        focus: function() {
            // prevent value inserted on focus
            return false;
        },
        select: function(event, ui) {
            var terms = split(this.value);
            // remove the current input
            terms.pop();
            // add the selected item
            terms.push(ui.item.value);
            // add placeholder to get the comma-and-space at the end
            terms.push("");
            this.value = terms.join(", ");
            return false;
        }
    });
}

function init_compose(id) {
    // Authorize dragging.
    $(id).ready(function () {
        $(id).draggable({ cursor: 'move' });
        // Activate autocompletion on input fields.
        init_autocomplete(id + "-to-input");
        init_autocomplete(id + "-cc-input");
        init_autocomplete(id + "-bcc-input");
    })
}

function init_chooser(id) {
    // Authorize dragging.
    $(id).ready(function () {
        $(id).draggable({ cursor: 'move' });
    })
}

$(document).ready(function() {

    $("body")
    .tooltip({ selector: '*[rel=tooltip]' })
    .popover({ selector: '*[rel=popover]' });

    $("#choose_file_modal").draggable({ cursor: 'move' });
        // handle: 'h3',
        // containment: 'body'

    $("#choose_folder_modal").draggable({ cursor: 'move' });
    $("#choose_label_modal").draggable({ cursor: 'move' });
    $("#choose_user_modal").draggable({ cursor: 'move' });
    $("#choose_team_modal").draggable({ cursor: 'move' });
    $("#modal_upload").draggable({ cursor: 'move' });

    // Labels

    // $("#labels_input")
    // 	// .tokenInput("/user/labels", {
    // 	//     queryParam: "term",
    // 	//     tokenValue: "value",
    // 	//     propertyToSearch: "label",
    // 	//     preventDuplicates: true,
    // 	//     //tokenLimit: 1,
    // 	//     theme: "facebook",
    // 	//     hintText: null,
    // 	//     minChars: 0
    // 	// });
    // 	.bind("keydown", function(event) {
    // 	    // don't navigate away from the field on tab when selecting an item
    // 	    if (event.keyCode === $.ui.keyCode.TAB &&
    // 		$(this).data("autocomplete") &&
    // 		$(this).data("autocomplete").menu.active) {
    // 		event.preventDefault();
    // 	    }
    // 	})
    // 	.autocomplete({
    // 	    minLength: 0,
    // 	    source: function(request, response) {
    // 		$.getJSON("/_user/labels", {
    // 		    term: extractLast(request.term)
    // 		}, response);
    // 	    },
    // 	    focus: function() {
    // 		// prevent value inserted on focus
    // 		return false;
    // 	    },
    // 	    select: function(event, ui) {
    // 		var terms = split(this.value);
    // 		// remove the current input
    // 		terms.pop();
    // 		// add the selected item
    // 		terms.push(ui.item.value);
    // 		// add placeholder to get the comma-and-space at the end
    // 		terms.push("");
    // 		this.value = terms.join(", ");
    //             $("*[rel=popover]").popover('hide');
    // 		return false;
    // 	    }
    // 	})
    // 	.on("autocompletechange", blur);

    // if ($("#labels_input").data("autocomplete")) {
    // 	$("#labels_input").data("autocomplete")._renderItem = label_renderer;
    // }

    // // Security labels

    // $("#security_labels_input")
    // 	.bind("keydown", function(event) {
    // 	    // don't navigate away from the field on tab when selecting an item
    // 	    if (event.keyCode === $.ui.keyCode.TAB &&
    // 		$(this).data("autocomplete") &&
    // 		$(this).data("autocomplete").menu.active) {
    // 		event.preventDefault();
    // 	    }
    // 	    // Do not accept normal keys
    // 	    // return belongs(event.keyCode, $.ui.keyCode);
    // 	})
    // 	.autocomplete({
    // 	    minLength: 0,
    // 	    source: function(request, response) {
    // 		$.getJSON("/_user/security_labels", {
    // 		    term: extractLast(request.term)
    // 		}, response);
    // 	    },
    // 	    focus: function() {
    // 		// prevent value inserted on focus
    // 		return false;
    // 	    },
    // 	    select: function(event, ui) {
    // 		this.value = ui.item.value;
    //             $("*[rel=popover]").popover('hide');
    // 		return false;
    // 	    }
    // 	})
    // 	.on("autocompletechange", blur);

    // if ($("#security_labels_input").data("autocomplete")) {
    // 	$("#security_labels_input").data("autocomplete")._renderItem = label_renderer;
    // }

    $(function () {
        $("#sidebar").bind('DOMNodeInserted DOMNodeRemoved', function(event) {
            auto_activate();
        });
    });

});
