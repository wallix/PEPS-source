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

module AdminController {

  private function log(msg) { Log.notice("[AdminController]", msg) }

  /** Check clearance of active user. */
  private function check_clearance(Login.state state, int level) {
    Login.is_super_admin(state) || (
      Login.is_admin(state) && (
      match (User.get_level(state.key)) {
        case {some: mylevel}: mylevel >= level
        default: false
      })
    )
  }

  exposed function register(fname, lname, username, password, int level, teams) {
    state = Login.get_state()
    is_admin = Login.is_admin(state)
    allowed = not(Admin.only_admin_can_register()) || is_admin
    if (not(allowed))
      Utils.failure(AppText.not_allowed_action(), {unauthorized})
    else if (Admin.only_admin_can_register() && not(check_clearance(state, level)))
      Utils.failure(AppText.Insufficient_clearance(), {forbidden})
    else if (String.is_empty(username))
      Utils.failure(@i18n("Please enter a username"), {bad_request})
    else if (String.is_empty(password))
      Utils.failure(@i18n("Please enter a password"), {bad_request})
    else if (User.username_exists(username))
      Utils.failure(@i18n("The username {username} already exists."), {conflict})
    else {
      sp = if (fname == "" || lname == "") "" else " "
      fullname = "{fname}{sp}{lname}"
      teams =
        if (Login.is_super_admin(state)) teams
        else User.get_teams(state.key)
      user =
        User.new(state.key, fname, lname, username,
          { address: {local: username, domain: Admin.get_domain()}, name: some(fullname) },
          level, teams, password)
      // Log user creation.
      Journal.Admin.log(state.key, user.key, {user: {new}}) |> ignore
      if (user.teams != []) Journal.Main.log(state.key, user.teams, {evt: {new}, user: user.key}) |> ignore
      // Initialize the file system
      // and create the base directories.
      Directory.init(user.key)
      // Initialize the mail system.
      Folder.init(user.key)
      // Import team messages.
      Folder.import(user.key, user.teams, [])
      // Update team user count.
      Team.register(user.teams) // Update team user count.
      // Initialize the contact list of the new user.
      // do Contact.init(user.key, Team.reduce(teams))
      Search.User.index(user) |> ignore

      {success: (is_admin, user)}
    }
  }

  /**  Bulk imports. */
  exposed function register_list(list, callback) {
    state = Login.get_state()
    function split(string path) { List.map(Utils.sanitize, String.explode_with("/", path, true)) }
    // Combine the results.
    recursive function combine(res, passwords, list, cbres) {
      match (cbres) {
       case ~{failure}: import([failure|res], passwords, list)
        case {success: _}: import(res, passwords, list)
      }
    }
    // Insert the next user.
    and function import(res, passwords, list) {
      match (list) {
        case [ (fname, lname, username, pass, level, teams) | tl ]:
          // Sanitize input.
          username = String.lowercase(username)
          pass = String.trim(pass)
          teams = List.map(split, teams)
          teams =
            List.filter_map(Team.new_from_path(state.key, Admin.get_domain(), _), teams) |>
            List.map(Team.get_path, _) |>
            List.flatten |> List.unique_list_of
          // Auto generate passwords.
          (pass, passwords) =
            if (pass == "") {
              pass = Random.string(8)
              (pass, ["{username}; {pass}"|passwords])
            } else
              (pass, passwords)
          Async.register(fname, lname, username, pass, level, teams, combine(res, passwords, tl, _))
        default:
          // Send email with passwords.
          if (passwords == []) callback({success: res})
          else {
            allpasses = String.concat("\n", passwords)
            attachement = File.create(state.key, "logins.txt", "text/plain", binary_of_string(allpasses), Label.attached.id)
            content = @i18n("The Bulk accounts have successfully been imported!\nSome missing passwords were automatically generated and added to the attached file.")
            MessageController.send_local_mail(state.key, "Bulk accounts", content, [attachement.file.id])
            callback({success: res})
          }
      }
    }
    import([], [], list)
  }

  protected function get_timeout() { Admin.get_settings().disconnection_timeout }
  exposed function get_grace_period() { Admin.get_settings().disconnection_grace_period }
  protected function get_domain_name() { Admin.get_settings().domain }
  protected function get_logo_name() { Admin.get_settings().logo }

  exposed @async function void set_settings(Admin.settings new_settings, callback) {
    state = Login.get_state()
    if (not(Login.is_admin(state)))
      callback({failure: AppText.not_allowed_action()})
    else if (new_settings.disconnection_timeout <= 0)
      callback({failure: @i18n("Negative timeout not allowed")})
    else if (new_settings.disconnection_grace_period <= 0)
      callback({failure: @i18n("Negative grace period not allowed")})
    else {
      domain = if (new_settings.domain == "") AppConfig.default_domain else new_settings.domain
      new_settings = { new_settings with ~domain }
      old_settings = Admin.get_settings()
      if (old_settings.disconnection_timeout != new_settings.disconnection_timeout)
        log("Disconnection timeout set to {new_settings.disconnection_timeout} minutes")
      if (old_settings.disconnection_grace_period != new_settings.disconnection_grace_period)
        log("Disconnection grace period set to {new_settings.disconnection_grace_period} seconds")
      if (old_settings.logo != new_settings.logo)
        log("Logo changed")
      if (old_settings.domain != new_settings.domain) {
        if (Utils.ask(AppText.Warning(), @i18n("Changing the domain means rewriting all user email addresses, do you wish to continue?"))) {
          log("Domain name set to {new_settings.domain}")
          Admin.changeSettings(new_settings,true)
          callback({success: (new_settings.disconnection_timeout, new_settings.disconnection_grace_period, domain)})
        } else
          callback({failure: @i18n("Administrator abort, not changing domain")})
      }else {
        Admin.changeSettings(new_settings,false)
        callback({success: (new_settings.disconnection_timeout, new_settings.disconnection_grace_period, domain)})
      }
    }
  }




  /** Management of external applications. */
  module App {

    /** App registration. */
    exposed @async function void create(name, url, callback) {
      state = Login.get_state()
      if (not(Login.is_super_admin(state))) callback({failure: AppText.unauthorized()})
      else @toplevel.App.create(name, url) |> config(_, callback)
    }

    /** Delete an existing application. The identifier is the app's consumer key. */
    exposed @async function void delete(key, callback) {
      state = Login.get_state()
      if (not(Login.is_super_admin(state))) callback({failure: AppText.unauthorized()})
      else {
        @toplevel.App.delete(key)
        callback({success})
      }
    }

    /** Return the list of applications. */
    exposed function list() {
      state = Login.get_state()
      if (not(Login.is_super_admin(state))) []
      else @toplevel.App.list()
    }

    /** Export app configuration (consumer secret) to the shared path /etc/peps/apps. */
    protected function config(result, callback) {
      match (result) {
        case {success: app}:
          port = Parser.parse(parser {
            case "http" ("s")? "://" (!":" .)* ":" port=Rule.integer .*: port
            case "http://" .*: 8080
            case "https://" .*: 4443
            case .*: 8080
          }, app.url)
          serverport = AppParameters.parameters.http_server_port ? AppConfig.http_server_port
          provider = "{Admin.get_domain()}:{serverport}"
          AppParameters.config(
            app.name, provider,
            app.oauth_consumer_key,
            app.oauth_consumer_secret,
            port
          )
        default: void
      }
      callback(result)
    }

  } // END APP

  /** Asynchrnous implementations of the controller functions. */
  module Async {
    @async @expand exposed function register(fname, lname, username, password, int level, teams, ('a -> void) callback) { AdminController.register(fname, lname, username, password, int level, teams) |> callback }
  }

}
