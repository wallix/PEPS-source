/** @externType TableSorter.parser */

/**
 * @register {string -> void}
 */
function init(sel) {
  $(sel).tablesorter();
}

/**
 * @register {TableSorter.parser -> void}
 */
function addParser(custom) {
  var format;
  if (custom.format.extract)
    format = function (s, table, cell, cellIndex) { return $(cell).attr(custom.format.extract); };
  else
    format = function (s, table, cell, cellIndex) { return custom.format.transform(s); };

  parser = {
    id: custom.id,
    is: function (s) { return false; },
    format: format
  }
  $.tablesorter.addParser(parser);
}

