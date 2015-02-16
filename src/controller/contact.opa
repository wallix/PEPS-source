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

module ContactController {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[ContactController]", msg) }
  private function warning(msg) { Log.warning("[ContactController]", msg) }

  /** {1} Controlled methods. */

  @async
  exposed function void save(Contact.t contact, Contact.t changed, callback) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      callback({failure: AppText.login_please()})
    // Contact update.
    else if (contact.id != Contact.dummy)
      if (contact.owner != state.key)
        callback({failure: AppText.unauthorized()})
      else {
        Contact.set(contact.id, changed)
        callback({success: changed})
      }
    // Contact creation.
    else if (changed.info.displayName != "") {
      // Import a profile picture, if possible.
      changed = Contact.with_picture(changed)
      changed = {changed with id: Contact.genid(), owner: state.key}
      Contact.insert(changed)
      callback({success: changed})
    } else
      callback({failure: AppText.no_contact_name()})
  }

  /** If contact is user profile, propagate the change to the user information. */
  exposed function set_picture(Contact.id id, File.id fid) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) {failure: AppText.login_please()}
    else
      match (Contact.get(id)) {
        case {some: contact}:
          if (contact.owner != state.key) {failure: AppText.unauthorized()}
          else
            // Function {FileController.get_thumbnail} checks both login and access to file.
          match (FileController.get_thumbnail(fid)) {
            case {some: (raw, thumbnail)}:
              Contact.set_picture(id, raw)
              if (id == state.key) User.set_picture(state.key, some(raw)) |> ignore
              {success: thumbnail}
            default:
              warning("Could not find file")
              {failure: AppText.missing_file(fid)}
          }
        default: {failure: AppText.unauthorized()}
      }
  }

  @async
  exposed function void block(Contact.t contact, bool block, callback) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      callback({failure: AppText.login_please()})
    else if (contact.owner != state.key)
      callback({failure: AppText.unauthorized()})
    else {
      status = if (block) {{blocked}} else {{normal}}
      contact = { contact with ~status}
      Contact.set_status(contact.id, status)
      callback({success: (contact, block)})
    }
  }

  @async
  exposed function void remove(Contact.t contact, callback) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      callback({failure: AppText.login_please()})
    if (contact.owner != state.key)
      callback({failure: AppText.unauthorized()})
    else {
      Contact.remove(contact.id)
      callback({success: contact})
    }
  }

  /** Check login and returns list of user contacts. */
  protected function get() {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      {failure: AppText.login_please()}
    else
      {success: Contact.get_all(state.key)}
  }

  /**
   * Fetch the contact information of the logged-in user.
   * If the contact is missing; initialize it using the information contained in User.t
   */
  protected function self() {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      {failure: AppText.login_please()}
    else
      match (Contact.get(state.key)) {
        case {some: contact}: {success: contact}
        default:
          match (User.get(state.key)) {
            case {some: user}: {success: Contact.profile(user)}
            default: {failure: AppText.login_please()}
          }
      }
  }

  /** Open a single contact. */
  protected function open(Contact.id id) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      {failure: AppText.login_please()}
    else
      match (Contact.get(id)) {
        case {some: contact}:
          if (contact.owner != state.key)
            {failure: AppText.unauthorized()}
          else
            {success: contact}
        default: {failure: AppText.Not_found()}
      }
  }

  /** Open a user as a contact. */
  protected function open_user(User.key key) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      {failure: AppText.login_please()}
    else
      match (User.get(key)) {
        case {some: user}:
          name = "{user.first_name} {user.last_name}"
          contact = Contact.make(state.key, name, user.email.address, {secret})
          {success: contact}
        default:
          {failure: "Not found"}
      }
  }

  /**
   * Import contacts from the list of accessible users.
   * Contact imports are deactivated as of now, but may be
   *   user triggered in the future.
   */
  protected function import(Login.state state) {
    teams = User.get_min_teams(state.key)
    Contact.import(state.key, teams)
  }

  module Async {
    @async @expand function set_picture(id, fid, ('a -> void) callback) { ContactController.set_picture(id, fid) |> callback }
  }

}
