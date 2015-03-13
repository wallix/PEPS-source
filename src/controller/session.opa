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



module SessionController {

  /*
   * Extract the active session token (in the last http request), if existing.
   * Token can be found in three locations:
   *
   *  - in the "Set-Cookie" header which we have to process manually
   *  - in the non-standard header value "X-Session-Token".
   */
  function get_session() {
    match (HttpRequest.get_cookie(AppConfig.auth_token)) {
      case {some: token}: {some: token}
      default: HttpRequest.get_headers() |> Option.bind(_.header_get("X-Session-Token"), _)
    }
  }

  /**
   * Create a new session for the logged in user, and return the oauth access token
   * generated for the session (only if the state is defined).
   */
  protected function option(string) create() {
    state = Login.get_state()
    if (Login.is_logged(state))
      match (User.get(state.key)) {
        case {some: user}:
          // Try predefined sessions.
          match (Sessions.find(user.key, user.status, false)) {
            case {some: token}: some(token)
            default:
              // Create a new session.
              token = Oauth.make_verified_token()
              Sessions.create(
                {key: user.key, status: user.status, username: user.username},
                some(token), false
              ) |> ignore
              some(token)
          }
        default: none
      }
    else none
  }

  /**
   * Logout the active user, which effects in the asscoiated
   * session being deleted.
   */
  exposed function logout() {
    match (get_session()) {
      case {some: token}: Sessions.delete(token)
      default: void
    }
  }

  /** Check validity of active session. */
  function valid() {
    match (get_session()) {
      case {some: token}: Sessions.valid(token)
      default: false
    }
  }

  /** Return the active session. */
  function get() {
    match (get_session()) {
      case {some: token}: Sessions.get(token)
      default: none
    }
  }

  /** Return the logged-in user. */
  function get_state() {
    match (get()) {
      case {some: session}:
        // Check validity of session.
        if (Sessions.validate(session))
          some({
            key: session.user.key,
            cred: User.cred_of_status(session.user.status)
          })
        else none
      default: none
    }
  }

}
