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


package com.mlstate.webmail.controller

module AutoComplete {

  /** {1} Log. **/

  private function log(msg) { Log.notice("[AutoComplete]", msg) }

  /** Addresses **/

  protected function addresses(state, term) {
    term = String.lowercase(term)
    contacts = Contact.autocomplete(state.key, term)
    users =
      User.autocomplete(User.get_min_teams(state.key), term) |>
      List.filter(function (i0) { not(List.exists(function (i1) { i0.label == i1.label }, contacts)) }, _) // Remove duplicates.
    teams = Team.autocomplete(User.get_teams(state.key), term)
    OpaSerialize.serialize(contacts ++ users ++ teams)
  }

  /** Labels **/

  // protected function labels(state, term, cat) {
  //   term = String.lowercase(term)
  //   labels = Label.autocomplete(state.key, cat)
  //   List.filter(function (e) {
  //     String.contains(String.lowercase(e.label), term)
  //   }, labels) |> OpaSerialize.serialize(_)
  // }

  /** Shared files **/

  // protected function shared_files(state, term, cat) {
  //   term = String.lowercase(term)
  //   files = FileToken.autocomplete(state.key, cat)
  //   //do Ansi.jlog("shared_files: files=%y{files}%d")
  //   List.filter(function (e) {
  //     String.contains(String.lowercase(e.file), term)
  //   }, files) |> OpaSerialize.serialize(_)
  // }

  /** JSON */

  exposed function json(string s) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) ""
    else {
      p = parser {
        case "/addresses?term=" term=(.*) -> addresses(state, Text.to_string(term))
        // case "/labels?term=" term=(.*) -> labels(state, Text.to_string(term), {personal})
        // case "/security_labels?term=" term=(.*) -> labels(state, Text.to_string(term), {security})
        // case "/shared_files?term=" term=(.*) -> shared_files(state, Text.to_string(term), {uploaded})
        case .* -> ""
      }
      Parser.parse(p, s)
    }
  }

}
