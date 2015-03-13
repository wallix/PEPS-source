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

  private function log(msg) { Log.notice("[AutoComplete]", msg) }

  /**
   * Search users and teams containg the provided term.
   * @return the search results in JSON format.
   */
  protected function addresses(state, term) {
    term = String.trim(term) |> String.lowercase
    contacts = Contact.autocomplete(state.key, term)
    users =
      User.autocomplete(User.get_min_teams(state.key), term) |>
      List.filter(function (i0) { not(List.exists(function (i1) { i0.text == i1.text }, contacts)) }, _) // Remove duplicates.
    teams = Team.autocomplete(User.get_teams(state.key), term)
    OpaSerialize.serialize({items: contacts ++ users ++ teams})
  }

}
