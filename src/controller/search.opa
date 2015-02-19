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

module SearchController {

  @async
  protected function void search(Login.state state, Mail.box box, string query, callback) {
    if (not(Login.is_logged(state)))
      callback({failure: AppText.login_please()})
    else
      match (AppConfig.search_type) {
        case {solr}: callback(Search.Message.search(state.key, box, query))
        case {mongo}: callback({success: SearchMongo.search(state.key, box, query)})
      }
      // TODO in postgres: |> List.filter(m -> MessageController.can_view(key, m.creator, m.labels), _)
      //do Notification.Broadcast.badges(state.key)
  }

  @async
  protected function void search_files(Login.state state, string query, callback) {
    if (not(Login.is_logged(state)))
      callback({failure: AppText.login_please()})
    else
      match (AppConfig.search_type) {
        case {solr}: callback(Search.File.search(state.key, query))
        case {mongo}: callback({failure: @i18n("No mongo file search implemented")})
      }
  }

  @async
  protected function void search_users(Login.state state, string query, callback) {
    if (not(Login.is_logged(state)))
      callback({failure: AppText.login_please()})
    else
      match (AppConfig.search_type) {
        case {solr}: callback(Search.User.search(query))
        case {mongo}: callback({failure: @i18n("No mongo user search implemented")})
      }
  }

  @async
  protected function void search_contacts(Login.state state, string query, callback) {
    if (not(Login.is_logged(state)))
      callback({failure: AppText.login_please()})
    else
      match (AppConfig.search_type) {
        case {solr}: callback(Search.Contact.search(state.key, query))
        case {mongo}: callback({failure: @i18n("No mongo contact search implemented")})
      }
  }

}
