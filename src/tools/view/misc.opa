/*
 * PEPS is a modern collaboration server
 * Copyright (C) 2015 MLstate
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */


package com.mlstate.webmail.tools.view

type Misc.chooser = {
	string id,    // Id of the dropdown VALUE container.
	list(string) options,
	string placeholder,
  option(string -> void) onselect,
	bool custom   // User can edit its own option.
}

module Misc {

  /**
   * Resposition an element, relatively to another.
   * FIXME= this is a temporary solution.
   * we want to avoid doing manual positioning of elements in javascript.
   * However, the class dropdown selector is currently placed inside of a table,
   * and if not for this fix, the drop down would disappear behind the following lines.
   *
   * @param string $refid
   *    dom element giving the destination
   * @param string $id
   *    dom element to move
   *
   * The element is going to be placed **under**
   */
  client function reposition(refid, id) {
    pos = Dom.get_position(#{refid})
    // pady = Dom.get_height(#{refid})
    // posy = pos.y_px + pady
    posx = pos.x_px
    Dom.set_attribute_unsafe(#{id}, "style", "left: {posx}px;")
    // Dom.set_attribute_unsafe(#{id}, "style", "top: {posy}px; left: {posx}px;")
  }

  /**
   * Perform a toggle on an element, with a two class:
   * switches between the two classes. The first class
   * is taken as reference for the state of the toggle.
   */
  client function toggle(id, c0, c1) {
    if (Dom.has_class(#{id}, c0)) {
      Dom.remove_class(#{id}, c0)
      Dom.add_class(#{id}, c1)
    }else {
      Dom.remove_class(#{id}, c1)
      Dom.add_class(#{id}, c0)
    }
  }

  /**
   * Convert a string list to a list of span elements.
   * @param divider if different from the empty string, intercalate a divider in between spans.
   */
  both function spanlist(class, xs) {
    recursive function fold(xs, acc) {
      match (xs) {
        case []: acc
        case [x]: acc <+> <span>{x}</span>
        case [x|xs]: fold(xs, acc <+> <span>{x}, </span>)
      }
    }
    <div class="{class}">
      {fold(xs, <></>)}
    </div>
  }

	function chooser(Misc.chooser chooser) {
    onselect = chooser.onselect ? ignore
		function select(string option, _evt) {
      #{"{chooser.id}"} = option
      onselect(option)
    }
		function custom(_evt) { void }
		// Dropdown menu.
    menu = List.fold(function (option, acc) {
      acc <+> <li><a onclick={select(option, _)}>{option}</a></li>
    }, chooser.options, <></>)
    // Add other options.
    menu =
    	if (chooser.custom) menu <+> <li><a onclick={custom}>{@intl("Custom...")}</a></li>
    	else menu

    <button type="button" data-toggle="dropdown" class="btn btn-default dropdown-toggle">
      <span id="{chooser.id}">{chooser.placeholder} </span><b class="caret"/></button>
    <ul class="dropdown-menu" role="menu">
      {menu}
    </ul>
	}

  /**
   * Display a date, converted to the client timezone.
   * @param date GMT date
   * @param printer format of the date display (the title fllows the default format)
   * @param plain if [true], return only the date in string format
   */
  client function date(Date.date date, bool plain, Date.printer printer) {
    prettydate = Date.to_formatted_string(printer, date)
    if (plain) <>{prettydate}</>
    else {
      title = Date.to_formatted_string(Date.default_printer, date)
      <div title={title} rel=tooltip data-placement=bottom>{prettydate}</div>
    }
  }

  /**
   * Display a timer, converted to the client timezone.
   * @param start date of the timer start, GMT
   */
  client function timer(Date.date start) {
    now = Date.now()
    start = if (start > now) now else start
    WDatePrinter.html(
      { WDatePrinter.default_config with
        server_date: {disable},
        duration_printer: default_printer },
      Dom.fresh_id(), start) |>
    Xhtml.add_attribute_unsafe("rel", "tooltip", _) |>
    Xhtml.add_attribute_unsafe("data-placement", "bottom", _)
  }

  /** Insert a date at the designated point. */
  client function insert_date(string id, Date.date date, string format)(_evt) {
    printer = Date.generate_printer(format)
    #{id} = Misc.date(date, false, printer)
  }

  /** Insert a date in plain format. */
  client function insert_plain_date(string id, Date.date date, string format)(_evt) {
    printer = Date.generate_printer(format)
    #{id} = Misc.date(date, true, printer)
  }

  /** Insert a timer at the designated point. */
  client function insert_timer(string id, Date.date start)(_evt) {
    #{id} = Misc.timer(start)
  }

  /**
   * The format for printing durations used by {!default_printer}.
   * NB: copied from Opa and modified to print [now] until one minute has passed.
   */
  both default_format =
    "[%>:[%D:[#=1:tomorrow :in ]]]" ^
    "[%Y:[#>0:# year[#>1:s] ][#=0:" ^
      "[%M:[#>0:# month[#>1:s] ][#=0:" ^
        "[%D:[#>1:# day[#>1:s] ][#=0:" ^ // we don't print days for #=1, because that was taken care with tomorrow/yesterday
          "[%h:[#>0:# hour[#>1:s] ][#=0:" ^
            "[%m:[#>0:# minute[#>1:s] :now ]" ^
    "]]]]]]]]]" ^
    "[%<:[%D:[#=1:yesterday :[%m:[#<1::ago ]]]]]"

  client default_printer = Duration.generate_printer(default_format)
}
