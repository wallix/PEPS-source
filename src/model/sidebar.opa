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


package com.mlstate.webmail.model

type Sidebar.view = {icons} or {folders}

type Sidebar.action = Dom.event -> void
type Sidebar.element =
	{ string id, string text, (Dom.event -> void) action } or // button
	{ string name,  // Name of the mode, used to determine the active element.
    string title, // Display name.
    string icon, // Icon.
    string id,    // Id used to generate the badge ID ({id}_badge).
    Sidebar.action onclick } or // activable item
	{ string separator, option(xhtml) button } or // static label
	{ xhtml content } // something else

type Sidebar.t = { Sidebar.options options, list(Sidebar.element) elements }

// TODO: local vs. global search
type Sidebar.options =
  { bool search,
    Sidebar.view view }

/** Signature of each sidebar module. */
type Sidebar.sign = {
  // (string -> Sidebar.options) options,
  (Login.state, Sidebar.options, string -> list(Sidebar.element)) build
}

/** Sidebar */
module Sidebar {

	default_options = {
    search: false,
    view: {folders}
  }

}
