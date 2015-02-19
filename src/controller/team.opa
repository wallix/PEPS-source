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

/** Type of json objects received by the API. */
type Team.insert = {
  string name,
  option(Team.key) parent,
  string description
}
type Team.update = {
  string name,
  string description
}

module TeamController {

  private function log(msg) { Log.notice("TeamController:", msg) }

  server @async function open(Team.key d, callback) {
    state = Login.get_state()
    if (Login.is_admin(state)) {
      users = User.find_by_team(0, [d])
      callback({success: {~users}})
    }
  }

  /**
   * Check the active user clearance.
   * @param d an optional edited team.
   * @param parent an optional parent folder.
   * @return [true] iff the active user can edit / create d.
   */
  function is_allowed(state, option(Team.key) d, option(Team.key) parent) {
    match (d) {
      // Edition: Check if active user is administrator of [d].
      case {some: d}: User.is_team_admin(state.key, d)
      // Creation: Chech whether active user is administrator of [parent].
      default:
        match (parent) {
          case {some: parent}: User.is_team_admin(state.key, parent)
          // Only super admins can create teams at toplevel.
          default: Login.is_super_admin(state)
        }
    }
  }

  /**
   * Save / create a team, after checking the active user clearance.
   * @param key is {none} if team creation, {some: _} if team update.
   * @param parent is the optional parent of the team.
   */
  exposed function save(option(Team.key) key, option(Team.key) parent, name, description) {
    state = Login.get_state()
    prevname = Option.bind(Team.get_name, key)
    name = String.lowercase(name)
    allowed = is_allowed(state, key, parent)
    if (not(Login.is_logged(state)))
      Utils.Failure.login()
    else if (not(allowed))
      Utils.failure(AppText.not_allowed_action(), {forbidden})
    else if (name == "")
      Utils.failure(@i18n("Please enter a team name"), {bad_request})
    // The condition prevname != {some: team_name} eliminates
    // the case where a team is modified but not its name.
    else if (prevname != {some: name} && Team.team_exists(name, parent))
      Utils.failure(@i18n("The team named [{name}] already exists"), {bad_request})
    else if (String.contains(name, ","))
      Utils.failure(@i18n("The team name must not contain the character ','"), {bad_request})
    else
      match (key) {
        case {some: key}:
          lparent = Utils.lofo(parent)
          Team.set(key, name, description)
          Journal.Admin.log(state.key, key, {team: {update}}) |> ignore
          Journal.Main.log(state.key, lparent, {evt: {update}, team: key}) |> ignore
          {success: key}
        default:
          email = Team.email(name, parent, Admin.get_domain())
          team = Team.new(state.key, name, email, parent, description)
          lparent = Utils.lofo(parent)
          Journal.Admin.log(state.key, team.key, {team: {new}}) |> ignore
          Journal.Main.log(state.key, lparent, {evt: {new}, team: team.key}) |> ignore
          {success: team.key}
      }
  }

  /**
   * Completely delete a team.
   * FIXME: we have to decide what to do about subteams: delete them too (after user confirm) ?
   */
  exposed function delete(Team.key key) {
    state = Login.get_state()
    allowed = is_allowed(state, {some: key}, {none})
    exists = Team.key_exists(key)
    if (not(Login.is_logged(state)))
      Utils.Failure.login()
    else if (not(exists))
      Utils.failure(@i18n("Non existent team"), {wrong_address})
    else if (not(allowed))
      Utils.failure(AppText.not_allowed_action(), {forbidden})
    else {
      parent = Team.get_parent(key)
      lparent = Utils.lofo(parent)
      Team.remove(key)
      Journal.Admin.log(state.key, key, {team: {delete}}) |> ignore
      if (lparent != []) Journal.Main.log(state.key, lparent, {evt: {delete}, team: key}) |> ignore
      {success}
    }
  }

  /**
   * REST api's get method.
   * Unlike users, files and messages, only one download format is available.
   * There is no restriction to the getting of one team's information.
   */
  protected function get(Team.key key) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      Utils.Failure.login()
    else
      match (Team.get(key)) {
        case {some: team}: {success: team}
        default: Utils.Failure.notfound()
      }
  }

  /**
   * REST api's list method.
   * Return all teams administrated by the active user.
   */
  protected function list() {
    state = Login.get_state()
    if (Login.is_super_admin(state))
      Team.key_list()
    else if (Login.is_admin(state))
      User.get_administrated_teams(state.key)
    else
      []
  }

  /** Asynchronous functions. */
  module Async {
    @async @expand function save(key, parent, name, description, ('a -> void) callback) { TeamController.save(key, parent, name, description) |> callback }
    @async @expand function delete(key, ('a -> void) callback) { TeamController.delete(key) |> callback }
  }
}
