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

module OauthController {

  private function log(msg) { Log.notice("OauthController: ", msg) }
  private function warning(msg) { Log.warning("OauthController: ", msg) }

  private function method(ff) {
    match (HttpRequest.get_method()) {
      case {some: method}: ff(method)
      default: {failure: @i18n("Unspecified HTTP method")}
    }
  }

  /**
   * Parse the authoriation header.
   * If successful, the parser returns the authorization scheme and a list of parameters.
   */
  binding = parser { Rule.ws x=([a-zA-Z0-9_]+) "=\"" v=((!"\"" .)*) "\"" : (Text.to_string(x), Uri.decode_string(Text.to_string(v))) }
  comma = parser { "," -> void }
  authorization = parser {
    Rule.ws scheme=([a-zA-Z]+) bindings=Rule.parse_list_sep(false, binding, comma): (Text.to_string(scheme), bindings)
  }

  /**
   * Extract the OAuth protocol parameters.
   * As indicated in the OAuth Core 1.0 protocol, the parameters may be
   * provided through one of the methods (tested in this order):
   *   - In the HTTP Authorization header as defined in OAuth HTTP Authorization Scheme.
   *   - As the HTTP POST request body with a content-type of application/x-www-form-urlencoded.
   *   - Added to the URLs in the query part (as defined by [RFC3986] section 3).
   *
   * The parameters are passed to the argument function.
   *
   * Note: the second method has been dropped for now, because accessing the body flushing its content
   * (implemented as a Binary.iter).
   */

  /** Extract query parameters. */
  protected function in_query() {
    url = HttpRequest.get_url()
    Option.map(_.query, url) ? []
  }
  /** Test HTTP body. */
  protected function in_body() {
    headers = HttpRequest.get_headers()
    contentType = Option.bind(_.header_get("content-type"), headers)
    match (contentType) {
      case {some: "application/x-www-form-urlencoded"}:
        form = HttpRequest.get_body()
        match (form) {
          case {some: form}:
            // StringMap.To.assoc_list(form)
            []
          default: []
        }
      default: []
    }
  }
  /** Test HTTP [Authorization] header. */
  protected function in_headers() {
    headers = HttpRequest.get_headers()
    auth = Option.bind(_.header_get("Authorization"), headers)
    match (auth) {
      case {some: auth}:
        match (Parser.try_parse(authorization, auth)) {
          case {some: (scheme, params)}:
            if (String.lowercase(scheme) == "oauth") params
            else []
          default: []
        }
      default: []
    }
  }
  /** Gather all parameters (including non-oauth query parameters). */
  protected function parameters() {
    // in_headers() ++ in_body(headers) ++ in_query()
    in_headers() ++ in_query()
  }


  function request_token(params) {
    function (http_method) { Oauth.get_request_token(http_method, params) } |> method
  }

  function authorize(oauth_token, oauth_callback) {
    Oauth.authorize(oauth_token, oauth_callback)
  }

  function access_token(params) {
    function (http_method) { Oauth.get_access_token(http_method, params) } |> method
  }

  function valid_request(params) {
    function (method) {
      path = HttpRequest.get_url() |> Option.map(_.path, _)
      path = path ? [] |> List.map(Uri.encode_string, _) |> String.concat("/", _)
      protocol = if (HttpRequest.is_secured() == some(true)) "https" else "http"
      defport = if (protocol == "https") "443" else "80"
      domain = (HttpRequest.get_host() ? some("")) ? ""
      domain = Parser.parse(parser {
        case host=((!":")+) ":{defport}": Text.to_string(host)
        case .*: domain
      }, domain)
      uri = "{protocol}://{domain}/{path}"
      Oauth.valid_request(method, uri, params)
    } |> method
  }

  /** Check request headers, and return corresponding state if successful. */
  function get_state() {
    params = parameters()
    match (List.assoc("oauth_token", params)) {
      case {some: token}:
        match (valid_request(params)) {
          case {success}:
            match (Sessions.user(token)) {
              case {some: user}: some({key: user.key, cred: User.cred_of_status(user.status)})
              default:
                warning("Unregistered access token")
                none
            }
          case ~{failure}:
            warning("OAuthController.get_state: invalid request: {failure}")
            none
        }
      default: none
    }
  }

}


