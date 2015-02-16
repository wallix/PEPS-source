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

type Ldap.t = {
  User.key key,
  string url,
  binary password,
  string binddn,
  string peopledn,
  int sync_ldap,
  int sync_mongo
}

type Ldap.validity =
  {none} or
  {Ldap.t invalid} or
  {Ldap.t valid}

database Ldap.t /webmail/ldaps[{key}]

module UserLdap {

  private function set(User.key key, Ldap.t ldap) {
    /webmail/ldaps[key == key] <- ldap
    get_cached_ldap.invalidate(key)
  }

  function add(User.key key, string url, string password, string binddn, string peopledn, int sync_ldap, int sync_mongo) {
    // match (AppSecurity.encrypt(binary_of_string(password))) {
      // case { none }: false
      // case { some : password }:
    password = binary_of_string(password)
    ldap = ~{key, url, password, binddn, peopledn, sync_ldap, sync_mongo}
    set(key, ldap)
    true
    // }
  }

  function remove(User.key key) {
    Db.remove(@/webmail/ldaps[key == key])
    get_cached_ldap.invalidate(key)
  }

  private function Ldap.validity priv_get(User.key key) {
    match (?/webmail/ldaps[key == key]) {
      case {none}: {none}
      case {some: ldap}:
        password = ldap.password
        // match (AppSecurity.decrypt(ldap.password)) {
          // case {none}: {invalid: ldap}
          // case {some: password}:
        {valid: {ldap with ~password}}
        // }
    }
  }

  private get_cached_ldap = AppCache.sized_cache(100, priv_get)

  @expand function get(User.key key) { get_cached_ldap.get(key) }

} // END LDAP
