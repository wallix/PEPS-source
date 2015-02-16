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

/**
 * Type of changes applied to the list of user teams.
 * This comes from the fact that only one of these operations can be performed
 * atomically. This helps the associated checks.
 */
type User.Team.change = {list(Team.key) added_teams, list(Team.key) removed_teams}


module UserController {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[UserController]", msg) }

  private function ldap_callback(name, key, callback, res) {
    match (res) {
      case {success:_}: callback({success: key})
      case ~{failure}: callback({failure: @i18n("LDAP {name} failure {failure}")})
    }
  }

  private function (list('a),list('a)) in_and_not_in(list('a) l1, list('a) l2) {
    List.partition(function (e1) { List.mem(e1,l2) }, l1)
  }

  /** Add empty highlightings to form displayable user items. */
  function highlight(users) { Iter.map(User.highlight(_, none, none, none), users) }
  /** Organize fetch results. */
  function page(users) { Utils.page(users, User.fullname, {fname: "", lname: ""}) }

  /** Return a fixed amount of users that can be viewed by the active user. */
  protected function fetch(state, User.fullname ref, User.filter filter, list(User.key) excluded) {
    // Super admins can see all users.
    teams = if (Login.is_super_admin(state)) [] else User.get_administrated_teams(state.key)
    teams = List.rev_append(teams, filter.teams) |> List.unique_list_of
    filter = {filter with ~teams}
    pagesize = AppConfig.pagesize
    page = User.fetch(ref, pagesize, Label.open.id, filter, excluded) |> highlight |> Iter.to_list |> page
    {page with more: true}
  }

  /** Fetch a user. */
  protected function open(Login.state state, User.key user) {
    if (not(User.is_user_admin(state.key, user))) Utils.Failure.forbidden()
    else
      match (User.get(user)) {
        case {some: user}: {success: user}
        default: Utils.failure(AppText.non_existent_user(), {wrong_address})
      }
  }

  /**
   * Check the validity of team changes.
   * @param teams updated list of ADMIN teams. In effect, all the teams uppath of these will be added.
   */
  exposed function update_teams(User.key key, User.Team.change changes) {
    state = Login.get_state()

    function check(teams) {
      (_, noexists) = List.partition(Team.key_exists, teams)
      if (noexists != []) {failure: "Non existent teams {String.concat(",", teams)}"}
      else {
        status = User.get_status(state.key)
        uteams = User.get_administrated_teams(state.key)
        (admin, notadmin) = in_and_not_in(teams, uteams)
        if (status != {super_admin} && notadmin != [])
          {failure: @i18n("You can only add/remove users to/from your own teams")}
        else
          {{success}}
      }
    }

    if (not(Login.is_logged(state)))
      {failure: AppText.not_allowed_action()}
    else if (not(User.is_user_admin(state.key, key)))
      {failure: AppText.not_allowed_action()}
    else
      match (check(changes.added_teams ++ changes.removed_teams)) {
        case {success}:
          previous = User.get_teams(key)
          min = Team.reduce(previous)
          // Only remove leaf teams.
          min = List.filter(function (t) { not(List.mem(t, changes.removed_teams)) }, min)
          // Add new teams.
          min = List.rev_append(min, changes.added_teams)
          // Generate new team set.
          new = List.rev_map(Team.get_path, min) |> List.flatten |> List.unique_list_of

          // For user updates.
          added = List.filter(function (t) { not(List.mem(t, previous)) }, new)
          removed = List.filter(function (t) { not(List.mem(t, new)) }, previous)
          // Insert new messages.
          Folder.purge(key, removed, new)
          Folder.import(key, added, previous)
          // Log team changes.
          if (added != []) Journal.Main.log(state.key, added, {evt: {new}, user: key}) |> ignore
          if (removed != []) Journal.Main.log(state.key, removed, {evt: {delete}, user: key}) |> ignore
          Journal.Admin.log(state.key, key, {user: {update}}) |> ignore
          Team.register(added)
          Team.unregister(removed)

          User.set_teams(key, new) |> ignore
          {success: new}
        case ~{failure}: ~{failure}
      }
  }

  /** TODO The condition: 'active user is admin of saved user' is not checked. */
  exposed function save(User.key key, int level, User.status status) {
    state = Login.get_state()
    if (not(Login.is_admin(state)))
      {failure: AppText.not_allowed_action()}
    else
      match (User.get_level(state.key)) {
        case {some: mylevel}:
          if (not(Login.is_admin(state)) && level > mylevel)
            {failure: AppText.Insufficient_clearance()}
          else if (User.update_level(key, level, status)) {
            Journal.Admin.log(state.key, key, {user: {update}}) |> ignore
            {success: key}

          } else
            {failure: @i18n("Update failed")}
        default: {failure: AppText.not_allowed_action()}
      }
  }

  exposed @async function void block(User.key key, bool block, callback) {
    state = Login.get_state()
    if (not(Login.is_admin(state)))
      callback({failure: AppText.not_allowed_action()})
    else {
      if (User.block(key, block))
        callback({success})
      else
        callback({failure: @i18n("Block failed")})
    }
  }

  exposed @async function void reset(User.key key, callback) {
    state = Login.get_state()
    if (not(Login.is_admin(state)))
      callback({failure: AppText.not_allowed_action()})
    else
      match (User.Password.reset(key)) {
        case {some: newpass}:
          callback({success: newpass})
        default:
          callback({failure: @i18n("Reset failed")})
      }
  }

  /**
   * TODO result of the LDAP update is not checked (because is asynchronous).
   *  If necessary: forcelly return from the async call to get the result.
   */
  protected function delete(Login.state state, User.key key) {
    if (not(User.is_user_admin(state.key, key)))
      Utils.failure(AppText.not_allowed_action(), {forbidden})
    else {
      teams = User.get_teams(key)
      User.unsafe_remove(key)
      if (teams != []) Journal.Main.log(state.key, teams, {evt: {delete}, user: key}) |> ignore
      Team.unregister(teams)
      Journal.Admin.log(state.key, key, {user: {delete}}) |> ignore
      {success}
    }
  }

  /**
   * Return a subset of the user fields, which depends upon the rights of the active user:
   *  - lambda: include key, full name, email, username
   *  - team admin or admin: include team, level and status as well
   */
  protected function get(User.key key, Message.format format) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      {failure: {unauthorized}}
    else
      match ((User.get(state.key), User.get(key))) {
        case ({some: admin}, {some: user}):
          // Check whether the required format is available.
          isadmin = User.Sem.is_user_admin(admin, user)
          match ((isadmin, format)) {
            case ({true}, {full}):
              {full: user}
            case (_, {minimal}):
              {minimal: ~{key, username: user.username, first_name: user.first_name, last_name: user.last_name, email: user.email}}
            default: {failure: {unauthorized}}
          }
        default: {failure: {not_found}}
      }
  }

  /** List users matching the given condition. */
  protected function list(option(string) pageToken, list(string) teamKeys, int maxResults) {
    state = Login.get_state()
    // Convert page token.
    ref = match (pageToken) {
      case {some: token}: User.get_fullname(User.idofs(token)) ? {lname: "", fname: ""}
      default: {lname: "", fname: ""}
    }
    // Build filter.
    filter =
      if (Login.is_admin(state)) {
        teams = User.get_administrated_teams(state.key)
        teams = List.rev_append(teams, teamKeys) |> List.unique_list_of
        ~{name: "", teams, level: 0}
      } else {name: "", teams: teamKeys, level: 0}
    // Fetch users (only if admin user).
    users =
      if (Login.is_admin(state)) User.fetch(ref, maxResults, Label.open.id, filter, [])
      else Iter.empty
    // Format response payload.
    page = users |> Iter.to_list |> page
    nextPageToken = List.head_opt(page.elts) |> Option.map(_.key, _)
    users = List.rev_map(function (user) { {key: user.key, username: user.username} }, page.elts)
    // Build payload.
    { resultSizeEstimate: page.size,
      users: users,
      nextPageToken: nextPageToken ? "" }
  }

  /**
   * Format a contact before saving it to memory.
   * In particular: make sure the internal email address is present, and propagate name changes to user.
   */
  exposed function format_contact(Contact.t contact) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) contact
    else if (state.key != contact.id) contact
    else
      match (User.get(state.key)) {
        case {some: user}:
          hasemail = List.exists(function (item) { item.elt == user.email.address }, contact.info.emails)
          match (String.explode(" ", contact.info.displayName)) {
            case [name]: User.set_name(state.key, "", name) |> ignore
            case [fname|lname]: User.set_name(state.key, fname, String.concat(" ", lname)) |> ignore
            default: void
          }
          if (hasemail) contact
          else {
            item = {kind: "work", elt: user.email.address}
            {contact with info.emails: [item|contact.info.emails]}
          }
        default: contact
      }
  }

  /** Expose protected functions. */
  module Expose {
    @expand function publish(check, method) {
      state = Login.get_state()
      if (not(check(state))) Utils.Failure.login()
      else method(state)
    }

    exposed function open(User.key user) { publish(Login.is_logged, UserController.open(_, user)) }
    exposed function delete(User.key user) { publish(Login.is_admin, UserController.delete(_, user)) }
  } // END EXPOSE

  /** Gather asynchronous version of the methods defined in UserController. */
  module Async {
    @async @expand function save(key, level, status, ('a -> void) callback) { UserController.save(key, level, status) |> callback }
    @async @expand function update_teams(key, changes, ('a -> void) callback) { UserController.update_teams(key, changes) |> callback }
    @async @expand function delete(key, ('a -> void) callback) { UserController.Expose.delete(key) |> callback }
    @async @expand function open(key, ('a -> void) callback) { UserController.Expose.open(key) |> callback }
  } // END ASYNC

}
