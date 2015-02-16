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

module Login {

  private function log(msg) { Log.notice("[Login]", msg) }

  loginbox_config = { WLoginbox.default_config with
    login_text: AppText.Sign_in(),
    stylers: { WLoginbox.default_config.stylers with
      submit: WStyler.make_class(["btn", "btn-primary"])
    }
  }

  private server_state = CLogin.make(anon_state, login_config)

  /**
   * Get the logged-in user.
   * The login state can originate from three different sources:
   *
   *  - regular login ; state stored in {server_state}
   *  - session token ; the session token is extracted from the cookies,
   *    and checked against stored sessions [src/model/session.opa]
   *  - OAuth connection ; the request signature is checked and the logged-in
   *    user identified based on the oauth_token.
   */
  protected function get_state() {
    // Check regular login.
    clogin = CLogin.get_state(server_state)
    if (clogin.cred != {anon}) clogin
    else
      // Check session token.
      match (SessionController.get_state()) {
        case {some: state}: state
        default:
          // Check OAuth connections.
          OauthController.get_state() ? anon_state
      }
  }

  login_config = CLogin.config(Login.data, Login.state, Login.credential) ~{
    authenticate, on_change, prelude: none,
    get_credential: function (state) { {
      full_name:
        if (state.key == anon_key) anon_name
        else
          match (User.get(state.key)) {
            case {some: user}: User.to_full_name(user)
            default: anon_name
          },
      cred: state.cred
    } },
    loginbox: function (do_change, cred) {
      function box(xhtml) {
        WLoginbox.html(
          loginbox_config, "loginbox",
          function (s1, s2) { do_change(some((s1, s2))) },
          xhtml
        )
      }
      match (cred.cred) {
        case {anon}: box(none)
        default: box(some(logout_xhtml(cred.full_name, do_change, none)))
      }
    }
  }

  server function authenticate(Login.data token, _state) {
    match (token) {
      case {some: (login, password)}:
        match (User.identify(login)) {
          case {some: key}:
            log("authenticating {login}")
            if (User.is_blocked(key)) none
            else
            if (User.Password.verify(key, password)) {
              log("valid token (PEPS)")
              status = User.get_status(key)
              some(~{key, cred: User.cred_of_status(status)})
            } else {
              log("invalid token")
              some(~{key, cred:{anon}})
            }
          default: none
        }
      default: none
    }
  }

  client function do_logout((Login.data -> void) do_change, option(Client.Anchor.handler) a_handler)(_evt) {
    log("logout: starting logout...")
    // Logout
    do_change(none)
    Dom.hide(#logged)
    log("logout: done")
    // Goto #
    Client.do_reload(true)
  }

  server function logout_xhtml(string name, (Login.data -> void) do_change, a_handler) {
      // <button type="button" class="btn btn-navbar navbar-toggle toggle-user"
      //    data-toggle="collapse" data-target=".nav-collapse">
      //    <span class="fa fa-user"/>
      // </button>
    <div>
      <ul class="nav navbar-nav nav-login">
        <li class="dropdown">
          <a class="dropdown-toggle"
              data-toggle="dropdown" id="profile_picture">
            <div class="user-img user-img-default"></div>
          </a>
          <ul class="dropdown-menu">
            <li class="dropdown-header">{String.capitalize(name)}</li>
            <li id=#settings_nav class="settings">
              <a href="/settings/profile">
                {AppText.settings()}
              </a>
            </li>
            <li class="divider"/>
            <li>
              <a onclick={do_logout(do_change, a_handler)}>
                {AppText.Logout()}
              </a>
            </li>
          </ul>
        </li>
      </ul>
    </div>
  }

  /** Tasks to be performed on login. XXX do as background task. */
  protected @async function onlogin() {
    void
  }

  /** On login / logout action */
  server function on_change(do_change, state) {
    log("on_change: new state {state}")
    if (is_logged(state)) {
      onlogin()
      Client.do_reload(true)
    }else if (Dom.is_empty(Dom.select_children(#loginbox_logged))) {
      error = WBootstrap.Alert.make(
        { alert: {title: AppText.Failure(), description: <>{AppText.invalid_username_password()}</>},
          closable: true},
        {error}
      )
      #notification_area = error
    }
  }

  anon_key = "anonymous"
  anon_name = "Anonymous"
  anon_state = {key: anon_key, cred: {anon}}

  function get_name(state) { state.key }
  function is_logged(state) { state.cred != {anon} }
  function is_super_admin(state) { state.cred == {super_admin} }
  function is_admin(state) {
    state.cred == {admin} || state.cred == {super_admin}
  }

  function logout() {
    clogin = CLogin.get_state(server_state)
    if (clogin.cred != {anon})
      CLogin.do_change(server_state, none)
  }

  protected function login(string login, string pass) {
    CLogin.do_change(server_state, some((login, pass)))
  }

  protected function build(state) {
    CLogin.html(server_state)
  }

}
