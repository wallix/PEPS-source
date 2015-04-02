/**
 * Copyright © 2015 MLstate
 *
 * @date 01/2015
 * @author HenriChataing
 */

package select2

/** Select 2 initial configuration. */
type Select2.options = {
  bool tags,
  bool allowClear,
  bool multiple,
  int minimumResultsForSearch, // Use a negative number to disable search.
  option(Select2.item -> xhtml) templateResult,
  option(Select2.item -> xhtml) templateSelection,
  list(string) tokenSeparators,
  Select2.placeholder placeholder,
  Select2.data data // Initial data.
  // There are many more...
}

/**
 * Private options (after pre-formatting).
 * The only difference lies in the templateResult field.
 */
abstract type Select2.Private.options = {
  bool tags,
  bool allowClear,
  bool multiple,
  int minimumResultsForSearch, // Use a negative number to disable search.
  option(Select2.item -> string) templateResult,
  option(Select2.item -> string) templateSelection,
  list(string) tokenSeparators,
  Select2.placeholder placeholder,
  Select2.data data // Initial data.
  // There are many more...
}

/** Type definitions. */
type Select2.item = {string text, string id}
type Select2.placeholder =
  {none} or {string string} or {Select2.item item}
type Select2.tokenSeparators = list(string)

type Select2.array = list(Select2.item)
type Select2.ajax = {
  // The number of milliseconds to wait for the user to stop typing before
  // issuing the ajax request. (use 250 as default).
  int delay,
  string url,             // Custom url.
  bool cache,             // Switch result caching.
  int minimumInputLength  // Input length required to send the query.
}
/** Data source. */
type Select2.data =
  {none} or
  {Select2.ajax ajax} or
  {Select2.array array}

module Select2 {

  /** Default initialization options. */
  defaults = Select2.options {
    tags: false,
    allowClear: false,
    multiple: false,
    minimumResultsForSearch: -1,
    tokenSeparators: [],
    placeholder: {none},
    data: {none},
    templateResult: none,
    templateSelection: none
  }

  /** Pre-format select2 options. */
  private function Select2.Private.options formatOptions(Select2.options options) {{
    tags: options.tags, allowClear: options.allowClear, data: options.data,
    placeholder: options.placeholder, multiple: options.multiple,
    minimumResultsForSearch: options.minimumResultsForSearch,
    tokenSeparators: options.tokenSeparators,
    templateResult:
      match (options.templateResult) {
        case {some: format}: some(function (item) { format(item) |> Xhtml.to_string })
        default: none
      },
    templateSelection:
      match (options.templateSelection) {
        case {some: format}: some(function (item) { format(item) |> Xhtml.to_string })
        default: none
      }
  }}

  /** Initialize select2 on an object. */
  client function init(dom dom, Select2.options options) {
    %%select2.init%%(Dom.to_string(dom), formatOptions(options))
  }

  /** Return the list of selected ids (or the text value in case of tags). */
  client function list(string) getSelection(dom dom) {
    %%select2.getSelection%%(Dom.to_string(dom))
  }

  /** Set the list of selected items. */
  client function void setSelection(dom dom, list(Select2.item) items) {
    %%select2.setSelection%%(Dom.to_string(dom), List.map(_.id, items))
  }
}
