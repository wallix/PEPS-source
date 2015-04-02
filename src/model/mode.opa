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

type Mode.t =
  {Mail.box messages} or
  {string files} or
  {string share} or
  {string people} or
  {string admin} or
  {string settings} or
  {string dashboard} or // either 'all' or 'team' (defaults to team)
  {string app, string active} or
  {error}

/**
 * It would seem like a good idea to use these
 * to define submodes, but it breaks the signature
 * of the Sidebar submodules.
 * => Replaced by strings.
 */

/*
type Mode.people =
  {contacts} or
  {users} or
  {teams}

type Mode.settings =
  {profile} or
  {display} or
  {signature} or
  {folders} or
  {labels} or
  {smtp}

type Mode.admin =
  {settings} or
  {classification} or
  {logging} or
  {indexing} or
  {bulk} or
  {ldap} or
  {smtp_out} or
  {smtp_in}
*/

module Mode {

  /** Identify topbar modes. */
  equiv = function(Mode.t a, Mode.t b) {
    match((a, b)){
      // different apps are not considered equivalent
      case ({messages: _}, {messages: _})
      case ({dashboard: _}, {dashboard: _})
      case ({people: _}, {people: _})
      case ({share: _}, {share: _})
      case ({admin: _}, {admin: _})
      case ({files: _}, {files: _}): true
      case ({app: app0 ...}, {app: app1 ...}): app0 == app1
      default: a == b
    }
  }

  function is_share(Mode.t mode) { equiv(mode, {share: ""}) }

  title = function {
    case ~{messages}: Box.name(messages)
    case {dashboard: _}: AppText.dashboard()
    case {files: _}: AppText.files()
    case {share: _}: AppText.share()
    case ~{people}: @intl("People ({people})")
    case ~{admin}: @intl("Admin ({admin})")
    case ~{settings}: @intl("Settings ({settings})")
    case ~{app, active}: "{app}: {active} (plugin)"
    case {error}: "#?%/"
  }

  active = function {
    case ~{messages}: Box.identifier(messages)
    case ~{files}: files
    case ~{share}: share
    case ~{people}: people
    case ~{admin}: admin
    case ~{settings}: settings
    case {app: _, ~active}: active
    case ~{dashboard}: dashboard
    case {error}: ""
  }

  name = function {
    case ~{messages}: Box.print_no_intl(messages)  // See comment on anchor(mails). The name is used to check if anchor is the same.
    case ~{files}:
      if (files == "") "files"
      else "files:{files}"
    case {share: link}: "share/{link}"
    case ~{people}: "people/{people}"
    case ~{admin}: "admin/{admin}"
    case ~{settings}: "settings/{settings}"
    case ~{app, active}: "app/{app}/{active}"
    case {error}: "#?%/"
    case ~{dashboard}: "dashboard:{dashboard}"
  }

  /**
   * Return the category a mode belongs to.
   * E.g. [{people: "contacts"}] is of category [people].
   */
  class = function {
    case {messages: _}: "messages"
    case {files: _}: "files"
    case {share: _}: "files"
    case {people:_}: "people"
    case {admin: _}: "admin"
    case {settings: _}: "settings"
    case {dashboard: _}: "dashboard"
    case ~{app, active}: app
    case {error}: "#?%/"
  }

  /** Return [true] iff the mode is unprotected. */
  unprotected = function {
    case {share: link}: Share.unprotected(link)
    default: false
  }

  /** Determine whether the mode is active or not. */
  function isActive(Mode.t mode) {
    urn = URN.get()
    class = Mode.class(mode)
    equiv(urn.mode, mode) || Dom.has_class(#{"sidebar_{class}"}, "app-visible")
  }
}
