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

SettingsController = {{

  /** {1} Utils. */

  log = Log.notice("[SettingsController]", _)

  /** Keygen. */



  /** preferences **/

 @server_private
  onboarding(key:User.key) =
    match User.get_preferences(key)
    {none} -> true
    {some=preferences} -> preferences.onboarding

  @server_private
  view(key:User.key) =
    match User.get_preferences(key) with
    {none} -> AppConfig.default_view
    {some=preferences} -> preferences.view

  @server_private
  get_user_preferences(key:User.key) =
    match User.get_preferences(key)
    {none} ->
      ( AppConfig.default_view, AppConfig.default_notifications, AppConfig.default_search_includes_send, true )
    {some=preferences} ->
      ( preferences.view, preferences.notifications, preferences.search_includes_send, preferences.onboarding )

  @publish @async
  save_user_preferences(view:Sidebar.view, notifications, search_includes_send, onboarding, callback) : void =
    state = Login.get_state()
    if not(Login.is_logged(state)) then
      callback({failure=AppText.login_please()})
    else
      preferences = {
        view = view
        notifications = notifications
        search_includes_send = search_includes_send
        topbar = [] // FIXME
        onboarding = onboarding
      }
      do User.add_preferences(state.key, preferences)
      callback({success= view})

  @publish @async
  save_user_signature(sgn, callback) : void =
    state = Login.get_state()
    if not(Login.is_logged(state)) then
      callback({failure=AppText.login_please()})
    else
      res = User.set_signature(state.key, sgn)
      callback(res)

  @publish @async
  save_user_password(oldpass, newpass, callback) : void =
    state = Login.get_state()
    if not(Login.is_logged(state)) then
      callback({failure=AppText.login_please()})
    else
      res = User.Password.set(state.key, oldpass, newpass)
      callback(res)

  @publish @async
  save_user_name(fname, lname, callback) : void =
    state = Login.get_state()
    if not(Login.is_logged(state)) then
      callback({failure=AppText.login_please()})
    else
      success = User.update(state.key, user ->
        fullname = "{fname} {lname}"
        { user with
          first_name = fname
          last_name = lname
          email.name = some(fullname)
        }
      )
      if (success) then
        callback({success})
      else
        callback({failure=AppText.inexistent_user()})

}}
