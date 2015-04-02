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


package com.mlstate.webmail.view

type FileRef.onclick = (string, FileRef.selected, Dom.event -> void)

/** Kind of action triggered by a click on the name of an item. */
type Table.onclick =
  {inert} or
  {FileRef.onclick immediate} or
  { {team} or       // Team sharing URLs:    /files:share/id/path
    {personal} or   // Private URLs:         /files/path or /raw/id
    {shared} link } // Public sharing URLs:  /share/id/path

type Table.column =
  {Table.onclick name} or           // Name column, with a specified onclick behaviour.
  {created} or                      // Creation date.
  {edited} or                       // Date of last edition.
  {{team} or {user} owner} or       // Owner of the file/directory, with an indication as of the kind of owner.
  {origin} or                       // Origin of the item.
  {size} or                         // For files: size.
  {mimetype} or                     // For files: mimetype.
  {class} or                        // Security class.
  {link} or                         // Public links.
  {FileRef.onclick checkbox}        // Checkboxes.

type Table.line =
  list(Table.column)

module Table {

  /** {1} Utils. */

  private function log(msg) { Log.notice("Table: ", msg) }

  /** {1} Custom parser. */

  size_parser = {
    id: "size",
    format: {extract: "data-size"},
    ctype: {numeric}
  }

	/** {1} Table headers. */

  private function column_header(Table.column column) {
    match (column) {
      case {name: _}: {xhtml: <>{AppText.name()}</>}
      case {created}: {xhtml: <>{AppText.created()}</>}
      case {edited}: {xhtml: <>{@intl("Edited")}</>}
      case {owner: _}: {xhtml: <>{AppText.owner()}</>}
      case {origin}: {xhtml: <>{AppText.shared_by()}</>}
      case {size}:
        { xhtml: <>{AppText.size()}</>,
          decorator: Xhtml.add_attribute_unsafe("data-sorter", "size", _) }
      case {mimetype}: {xhtml: <>{AppText.kind()}</>}
      case {class}: {xhtml: <>{@intl("Class")}</>}
      case {checkbox: onclick}: {xhtml: <></>}
      case {link}: {xhtml: <>{AppText.link()}</>}
    }
  }

  function headers(Table.line columns) {
    List.rev_map(column_header, columns)
  }

  /** {1} Column rendering. */

  /* Render a single line. */
  function WBootstrap.Table.line render(renderer, handles, Table.line columns) {
	  columns = List.rev_map(renderer, columns)
	  { elts: columns,
	    handles: handles }
	}

	/** Build a table with files and directories. */
	function build(content, renderers, headers) {
		content =
			List.rev_map(renderers.directory(_, headers), content.directories) |>
    	List.fold(function(token, acc) { [ renderers.file(token, headers) | acc ] }, content.files, _)

    if (content == [])
      <div class="empty-text">{AppText.empty_folder()}</div>
    else
      <div onready={function(_) {
          TableSorter.addParser(size_parser)
          TableSorter.init(Dom.select_class("tablesorter"))
        }}>{
        WB.Table.hover(Table.headers(headers), content) |>
        Xhtml.update_class("table-responsive table-hover tablesorter tablesorter-bootstrap", _)
      }</div>
	}

}
