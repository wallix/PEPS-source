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



/**
 * Identification of the session user.
 * The {key} and {status} will be used to generate the login state.
 */
type Session.user = {
  User.key key,
  User.status status,
  string username
}

/**
 * Session definitions.
 * Sessions bind an authorized token to the corresponding user.
 * It also contains such information as the expiration date, the ip
 * of the user, the renewing mode...
 */
type Session.t = {
  string token,  // Authorized OAuth token.
  Session.user user,
  Date.date date, // Session creation.
  Date.date expires, // Exporation date.
  // Additional user information.
  option(ip) ip,
  option(user_compat) ua,
  bool autorenew // Automatically renew this session, usefull for session cookies.
}

database sessions @mongo {
  Session.t /sessions[{token}]
}

database /sessions/sessions[_]/autorenew = false
database /sessions/sessions[_]/user full
database /sessions/sessions[_]/ua full

/** Manages remote sessions. */
module Sessions {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[Session]", msg) }
  private function debug(msg) { Log.debug("[Session]", msg) }

  /** {1} Session creation. */

  function Session.t create(Session.user user, option(string) token, bool cookie) {
    date = Date.now()
    token = token ? Random.generic_string("abcdefghijklmnopqrstuvwxyz0123456789", 16)
    expires =
      if (cookie) Date.advance(Date.now(), Duration.h(AppConfig.session_cookie_validity))
      else Date.advance_by_days(Date.now(), AppConfig.cookie_validity)
    session = ~{
      token, user, date: Date.now(), expires,
      ip: HttpRequest.get_ip(), ua: HttpRequest.get_user_agent(),
      autorenew: cookie
    }
    /sessions/sessions[token == token] <- session
    session
  }

  /** {1} Getters. */

  @expand function get(token) { ?/sessions/sessions[token == token] }
  @expand function user(token) { ?/sessions/sessions[token == token]/user }

  /** {1} Properties. */

  /** Check the session date validity. */
  function validate(Session.t session) {
    valid = Date.now() < session.expires
    if (session.autorenew && valid) {
      // Push back the expiration date.
      expires = Date.advance(Date.now(), Duration.h(AppConfig.session_cookie_validity))
      /sessions/sessions[token == session.token]/expires <- expires
      true
    } else valid
  }
  function valid(string token) {
    match (get(token)) {
      case {some: session}: validate(session)
      default: false
    }
  }

  /** {1} Updates. */

  /** Change the token of a session. */
  function swap(string token, string newtoken) {
    if (Db.exists(@/sessions/sessions[token == token]))
      /sessions/sessions[token == token] <- {token: newtoken}
  }

  /** Delete a specific session. */
  function delete(string token) {
    Db.remove(@/sessions/sessions[token == token])
  }

  /** Delete all sessions for a user. */
  function disconnect(User.key key) {
    DbSet.iterator(/sessions/sessions[user.key == key]/token) |>
    Iter.iter(delete, _)
  }

  /** Update token credentials. */
  function update_credentials(token, status) {
    /sessions/sessions[token == token] <- {user.status: status; ifexists}
  }

  /**
   * Find a token associated with the provided user, and check its validity.
   * If a token exists, but is not valid, it will be removed from the database.
   * Else, the rights of the user are updated.
   *
   * @param secret if [true], validate only tokens with non empty secrets.
   * @param is_admin credentials of the active user.
   */
  protected function find(User.key key, User.status status, bool secret) {
    recursive function try(iter(string) tokens) {
      match (tokens.next()) {
        case {some: (token, more)}:
          if (Oauth.validate_token(token, secret)) {
            update_credentials(token, status) // Update user credentials.
            some(token)
          } else {
            log("Found token, but not valid.")
            delete(token)
            try(more)
          }
        default: none
      }
    }

    // Try all user tokens, until a valid one is found.
    DbSet.iterator(/sessions/sessions[user.key == key]/token) |> try
  }

}
