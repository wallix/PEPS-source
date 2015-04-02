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

module LabelController {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[LabelController]", msg) }

  /** {1} Controller methods. */

  /**
   * Open a label tab info. Depending on the mode {admin}, the tab will contain:
   *  - messages if not admin
   *  - users otherwise
   */
  protected @async function open(Login.state state, Label.t label, bool admin, ('a -> void) callback) {
    // if (Login.is_logged(state))
    if (admin && Login.is_admin(state)) {
      users = match (label.category) {
        case {classified: restriction}: User.find_matching_restriction(restriction)
        default: User.iterator()
      }
      callback({success: ~{users}})
    }else if (Login.is_logged(state)) {
      messages = MessageController.get_messages_of_label(state.key, label.id)
      callback({success: {~messages, label: label.name}})
    }
  }

  /**
   * Save changes made to an existing label, or create a new one, depending on the value of
   * the identifier.
   */
  protected function save(Login.state state, option(Label.id) previd, name, descr, category) {
    allowed =
      match (previd) {
        case {some: id}: Label.KeySem.user_can_edit_label(state.key, id)
        case {none}: Login.is_super_admin(state) || not(Label.is_security_category(category))
      }
    if (not(allowed))
      {failure: AppText.not_allowed_action()}
    else if (name == "")
      {failure: @intl("Please enter a label name")}
    else if (previd == {none} && Label.name_exists(name, state.key))
      {failure: @intl("The label named [{name}] already exists")}
    else if (String.contains(name, ","))
      {failure: @intl("The label name must not contain the character ','")}
    else
      match (previd) {
        case {some: id}:
          Label.set(id, name, descr, category)
          {success: id}
        case {none}:
          label = Label.new(state.key, name, descr, category)
          {success: label.id}
      }
  }

  /**
   * Delete a single label. Rules for deletion are as follow:
   *  - only super admins can delete security classes
   *  - otherwise, only the label owner can decide to remove it
   */
  protected function delete(Login.state state, Label.id id) {
    match (Label.safe_get(state.key, id)) {
      case {some: label}:
        if (not(Login.is_super_admin(state)) && Label.is_security(label))
          {failure: AppText.not_allowed_action()}
        else if (Label.delete(id)) {success: void}
        else {failure: @intl("Error during deletion")}
      default: {failure: AppText.Label_not_found()}
    }
  }

  /** {1} Aliases. */

  module Exposed {
    @expand function publish(method) {
      state = Login.get_state()
      if (not(Login.is_logged(state))) {failure: AppText.login_please()}
      else method(state)
    }

    exposed function save(id, name, descr, category) { publish(LabelController.save(_, id, name, descr, category)) }
    exposed function delete(id) { publish(LabelController.delete(_, id)) }
  } // END EXPOSED

  module Async {
    @async @expand function save(id, name, description, category, ('a -> void) callback) { LabelController.Exposed.save(id, name, description, category) |> callback }
    @async @expand function delete(id, ('a -> void) callback) { LabelController.Exposed.delete(id) |> callback }
  } // END ASYNC

}
