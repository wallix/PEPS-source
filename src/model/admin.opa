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

type Admin.settings = {
  int disconnection_timeout, // minutes
  int disconnection_grace_period, // seconds
  string domain,
  bool only_admin_can_register,
  string logo
}

database Admin.settings /webmail/settings
database /webmail/settings/only_admin_can_register = AppConfig.only_admin_can_register

module Admin {

  private default_settings = {
    disconnection_timeout: AppConfig.default_timeout,
    disconnection_grace_period: AppConfig.default_grace_period,
    domain: AppParameters.parameters.domain ? AppConfig.default_domain,
    only_admin_can_register: AppConfig.only_admin_can_register,
    logo: "PEPS"
  }

  function init() {
    match (?/webmail/settings) {
      case {some:_}: void
      default: /webmail/settings <- default_settings
    }
  }

  /** Create the admin user. */
  function create(string password) {
    email = {
      address: {
        local: AppConfig.admin_login,
        domain: Admin.get_domain()
      },
      name: some(AppConfig.admin_name)
    }
    DbUtils.log("Adding {AppConfig.admin_login} user with email {email}")
    admin = User.new(
      "god", "", AppConfig.admin_name, AppConfig.admin_login, email,
      AppConfig.admin_level, [], password
    )
    // Create initial directories.
    Directory.init(admin.key)
    User.set_status(admin.key, {super_admin}) |> ignore
  }

  /** Identify first launch. (Condition attained when admin user is undefined). */
  function undefined() {
    User.get_key("admin") |> Option.is_none
  }

  /** Change the domain, without propagating the changes. */
  function set_domain(string domain) {
    /webmail/settings/domain <- domain
    settingsCache.invalidate({})
  }

  private settingsCache =
    AppCache.sized_cache(1, function(void _void) {
      ?/webmail/settings ? default_settings
    })


  function settings() { settingsCache.get(void) }
  exposed function get_domain() { settings().domain }
  function only_admin_can_register() { settings().only_admin_can_register }

  @expand function logo() { settings().logo }
  @expand function shortLogo() { Utils.string_limit(9, settings().logo) }


  /**
   * Change the admin settings.
   * @param updateDomain whether to propagate the new domain to all registered users.
   */
  function changeSettings(Admin.settings settings, bool updateDomain) {
    // Update domain iff no license.

    /webmail/settings <- settings
    settingsCache.invalidate(void)

    if (updateDomain)
      Iter.iter(function (User.t user) {
        if (user.email.address.domain != settings.domain) {
          email = {user.email with address:{user.email.address with domain:settings.domain}}
          User.set_email(user.key, email) |> ignore
        }
      }, User.iterator())

    // Update all but domain.
  }

}
