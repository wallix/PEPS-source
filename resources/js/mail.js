/**
 * @author (c) MLstate, 2011 - 2015
 */

/** auto-activate navbar items and list-group items. */
function autoActivate() {
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

/** Enable modal dragging. */
function setDraggable(id) {
  $(id).ready(function () {
    $(id).draggable({ cursor: 'move' });
  })
}

/** Initialize client content. */
$(document).ready(function() {

  $("body")
    .tooltip({ selector: '*[rel=tooltip]' })
    .popover({ selector: '*[rel=popover]' });

  $("#modal_upload").draggable({ cursor: 'move' });

  $(function () {
    $("#sidebar").bind('DOMNodeInserted DOMNodeRemoved', function(event) {
      autoActivate();
    });
  });

});
