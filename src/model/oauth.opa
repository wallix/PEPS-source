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

/**
 * OAuth consumer, defined by an key pair.
 * Typically an external application.
 * Edit to change underlaying type.
 * A minimal type definition includes the fields:
 *
 *  - string oauth_consumer_key
 *  - string oauth_consumer_secret
 *  - string provider
 */
type Oauth.consumer = App.t

/**
 * Edit this value to change underlaying system.
 * Minimal definition should include the following methods:
 *
 *  - (string -> option(Oauth.consumer) get
 *  - ..
 */
Consumer = App

/** OAuth request tokens. */
type Oauth.request_token = {
  string oauth_token,
  string oauth_token_secret,
  string oauth_callback,
  string oauth_consumer_key, // Consumer for which the token was issued.
  Date.date expires
}

/** OAuth verified request tokens and access tokens. */
type Oauth.access_token = {
  string oauth_token,
  string oauth_token_secret,
  string oauth_verifier,
  string oauth_callback,
  Date.date expires
}

/** Implemented signature methods. */
type OAuth.signature_method =
  { PLAINTEXT } or // Plain text signature - Not recommended unless you have a https connection
  { HMAC_SHA1 }    // HMAC-SHA1 signature

database tokens @mongo {
  Oauth.request_token /request_tokens[{oauth_token}]
  Oauth.access_token /access_tokens[{oauth_token}]
}

module Oauth {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[OAuth]", msg) }
  private function warning(msg) { Log.warning("[OAuth]", msg) }
  private function debug(msg) { Log.debug("[OAuth]", msg) }
  private function error(msg) { Log.error("[OAuth]", msg) }

  /** Generate a fresh token. */
  function new_token() {
    Random.generic_string("abcdefghijklmnopqrstuvwxyz0123456789",16)
  }

  function make_oauth_url(path) {
    proto = if (AppParameters.parameters.no_ssl) "http" else "https"
    host = Admin.get_domain()
    port = AppParameters.parameters.http_server_port ? AppConfig.http_server_port
    url = if (port != 443) "{host}:{port}" else host
    url = "{proto}://{url}/{path}"
    debug("url={url}")
    url
  }

  function get_consumer(params) {
    oauth_consumer_key = List.assoc("oauth_consumer_key",params) ? ""
    match (oauth_consumer_key) {
    case "": (oauth_consumer_key, "")
    default:
      // match (?/tokens/tokens[oauth_consumer_key == oauth_consumer_key]) {
      match (Consumer.get(oauth_consumer_key)) {
        case {some: consumer}: (oauth_consumer_key, consumer.oauth_consumer_secret)
        default: (oauth_consumer_key, "")
      }
    }
  }

  function get_consumer_name(string oauth_token) {
    oauth_consumer_key = ?/tokens/request_tokens[oauth_token == oauth_token]/oauth_consumer_key
    Option.bind(Consumer.name, oauth_consumer_key)
  }

  function oauth_request_url() { make_oauth_url("api/v0/oauth/request_token") }
  function oauth_access_token_url() { make_oauth_url("api/v0/oauth/access_token") }

  /** {1} Request signature. */

  @stringifier(HttpRequest.method) http_method_to_string = function {
    case {post}: "POST"
    case {get}: "GET"
    case {head}: "HEAD"
    case {put}: "PUT"
    case {delete}: "DELETE"
    case {trace}: "TRACE"
    case {connect}: "CONNECT"
    case {options}: "OPTIONS"
    case ~{other}: other
  }

  @stringifier(OAuth.signature_method) sign_method_to_string = function {
    case {PLAINTEXT}: "PLAINTEXT"
    case {HMAC_SHA1}: "HMAC-SHA1"
  }

  sign_method_of_string = function {
    case "PLAINTEXT": some({PLAINTEXT})
    case "HMAC-SHA1": some({HMAC_SHA1})
    default: none
  }

  /**
   * Normalize parameters in order to build the request signature.
   * Check http://oauth.net/core/1.0/#anchor14 for process description.
   */
  function normalize_parameters(params) {
    function normalize((key, value)) { "{Uri.encode_string(key)}={Uri.encode_string(value)}" }
    List.map(normalize, params) |> List.sort |> String.concat("&", _) |> Uri.encode_string
  }

  /** HMAC-SHA1 signature method. */
  function hmac_sha1_sign(consumer_secret, token_secret, method, uri, params) {
    params = normalize_parameters(params)
    uri = Uri.encode_string(uri)
    method = http_method_to_string(method)
    base_string = "{method}&{uri}&{params}"
    key = Binary.of_string("{Uri.encode_string(consumer_secret)}&{Uri.encode_string(token_secret)}")
    base = Binary.of_string(base_string)
    Crypto.Base64.encode(Crypto.HMAC.sha1(key, base))
  }

  /** PLAINTEXT signature method. */
  function plaintext_sign(consumer_secret, token_secret) {
    "{Uri.encode_string(consumer_secret)}&{Uri.encode_string(token_secret)}"
  }

  /** Compute the signature of an incoming request. */
  function sign(sign_method, consumer_secret, token_secret, http_method, uri, params) {
    params = List.filter(function ((name,_)) { name != "oauth_signature" && name != "realm" }, params)
    match (sign_method) {
      case {PLAINTEXT}: plaintext_sign(consumer_secret, token_secret)
      case {HMAC_SHA1}: hmac_sha1_sign(consumer_secret, token_secret, http_method, uri, params)
    }
  }

  /**
   * Check the signature of a request.
   * Both signature and signature method are extracted from the parameters, and
   * the function returns false if one of them is missing.
   */
  function valid_sign(consumer_secret, token_secret, http_method, uri, params) {
    // Extract the signature and signature mtehod from the parameters.
    sign_method = List.assoc("oauth_signature_method", params) |> Option.bind(sign_method_of_string, _)
    signature = List.assoc("oauth_signature", params)
    match ((signature, sign_method)) {
      case ({some: signature}, {some: sign_method}):
        // Compare the computed signature with the extracted one.
        sign(sign_method, consumer_secret, token_secret, http_method, uri, params) == signature
      case ({none}, _):
        warning("Oauth.valid_sign: missing request signature")
        false
      default:
        warning("Oauth.valid_sign: missing request signature method")
        false
    }
  }

  /** {1} OAuth endpoints. */

  /** Request token end point. */
  function get_request_token(http_method, params) {
    // debug("get_request_token: params={params}")
    consumer_key = List.assoc("oauth_consumer_key", params)
    match (consumer_key) {
      // Request is for a temporary token
      case {some: ""} case {none}:
        // Signature check.
        if (valid_sign("", "", http_method, oauth_request_url(), params)) {
          oauth_token = new_token()
          oauth_token_secret = new_token()
          oauth_callback = List.assoc("oauth_callback", params) ? "oob"
          expires = Date.advance(Date.now(), Duration.h(AppConfig.oauth_temp_token_duration_hours))
          /tokens/request_tokens[oauth_token == oauth_token] <- ~{
            oauth_token, oauth_token_secret, oauth_callback,
            expires, oauth_consumer_key: ""
          }
          { success:
            [ ("oauth_token", oauth_token),
              ("oauth_token_secret", oauth_token_secret),
              ("oauth_callback_confirmed", "true") ] }
        } else
          {failure: @intl("Invalid signature")}
      // Known consumer.
      case {some: oauth_consumer_key}:
        match (Consumer.get(oauth_consumer_key)) {
          case {some: consumer}:
            if (valid_sign(consumer.oauth_consumer_secret, "", http_method, oauth_request_url(), params)) {
              oauth_token = new_token()
              oauth_token_secret = new_token()
              oauth_callback = List.assoc("oauth_callback", params) ? "oob"

              if (compareCallbacks(consumer.url, oauth_callback)) {
                expires = Date.advance(Date.now(), Duration.days(AppConfig.oauth_token_duration_days))
                /tokens/request_tokens[oauth_token == oauth_token] <- ~{
                  oauth_token, oauth_token_secret, oauth_callback,
                  expires, oauth_consumer_key
                }
                { success:
                  [ ("oauth_token",oauth_token),
                    ("oauth_token_secret",oauth_token_secret),
                    ("oauth_callback_confirmed","true") ] }
              } else
                {failure: @intl("App provider does not match callback: {consumer.url} != {oauth_callback}")}
            } else
              {failure: @intl("Invalid signature")}
          // Undefined consumer.
          default: {failure: @intl("Unknown consumer")}
        }
    }
  }

  /**
   * Auhtorize a request token: the request token is destroyed, whiled an access token is generated
   * along with a verifier.
   *
   * @param oauth_token the request token to be authorized.
   * @param oauth_callback override the callback registered at the creation of the request token.
   */
  function authorize(oauth_token, oauth_callback) {
    match (?/tokens/request_tokens[oauth_token == oauth_token]) {
      case {some: token}:
        // Identify new callback.
        oauth_callback = if (oauth_callback == "" || oauth_callback == "oob") token.oauth_callback else oauth_callback
        // Destroy previous request token.
        Db.remove(@/tokens/request_tokens[oauth_token == oauth_token])
        // If request token is still valid, generate new access token.
        if (Date.now() <= token.expires) {
          oauth_verifier = new_token()
          oauth_token_secret = token.oauth_token_secret
          expires = Date.advance(Date.now(), Duration.days(AppConfig.oauth_token_duration_days))
          /tokens/access_tokens[oauth_token == oauth_token] <- ~{oauth_token, oauth_token_secret, oauth_verifier, oauth_callback, expires}
          {success: ~{oauth_token, oauth_verifier, oauth_callback}}
        } else
          {failure: "Request token expired"}
      default: {failure: "Invalid request token"}
    }
  }

  /**
   * Access token endpoint.
   * Generate an access token from an authorized request token.
   */
  function get_access_token(http_method, params) {
    // debug("get_access_token: params={params}")
    (oauth_consumer_key, oauth_consumer_secret) = get_consumer(params)
    oauth_token = List.assoc("oauth_token",params) ? ""
    match (?/tokens/access_tokens[oauth_token == oauth_token]) {
      case {some: token}:
        if (valid_sign(oauth_consumer_secret, token.oauth_token_secret, http_method, oauth_access_token_url(), params)) {
          oauth_token = new_token()
          oauth_token_secret = new_token()
          oauth_verifier = List.assoc("oauth_verifier",params) ? ""
          if (oauth_verifier == token.oauth_verifier) {
            expires = Date.advance(Date.now(), Duration.h(AppConfig.oauth_token_duration_days))
            /tokens/access_tokens[oauth_token == oauth_token] <- ~{oauth_token, oauth_token_secret, oauth_callback:"", expires}
            Db.remove(@/tokens/access_tokens[oauth_token == token.oauth_token])
            {success:[("oauth_token",oauth_token), ("oauth_token_secret",oauth_token_secret)]}
          }else {
            warning("OAuth.get_access_token: invalid token verifier: oauth_token={oauth_token}")
            {failure:@intl("Authentication failure")}
          }
        }else
          {failure:@intl("Authentication failure")}
      default: {failure:@intl("Invalid token")}
    }
  }

  /** Check a request credentials (access token). */
  function valid_request(method, uri, params) {
    (oauth_consumer_key, oauth_consumer_secret) = get_consumer(params)
    oauth_token = List.assoc("oauth_token", params) ? ""
    match (?/tokens/access_tokens[oauth_token == oauth_token]) {
      case {some:token}:
        if (valid_sign(oauth_consumer_secret, token.oauth_token_secret, method, uri, params))
          {success: void}
        else {failure: @intl("Invalid signature")}
      default: {failure: @intl("Invalid token")}
    }
  }

  /**
   * Compare callback URLs.
   * URLs are declared compatible if either one is 'oob', or if they
   * have the same domain and port.
   */
  function compareCallbacks(string url0, string url1) {
    if (url0 == "oob" || url1 == "oob") true
    else
      match ((Uri.of_string(url0), Uri.of_string(url1))) {
        case (
          {some: {domain: domain0, port: port0 ...}},
          {some: {domain: domain1, port: port1 ...}}): domain0 == domain1 && port0 == port1
        default: false
      }
  }

  /**
   * Check the validity of the given token.
   * @param secret if true, validate only tokens whose scret is non empty, if false, only tokens with empty secrets.
   */
  function validate_token(oauth_token, bool secret) {
    match (?/tokens/access_tokens[oauth_token == oauth_token]) {
      case {some: token}:
        if (Date.now() > token.expires) {
          Db.remove(@/tokens/access_tokens[oauth_token == oauth_token])
          false
        } else if (secret)
          token.oauth_token_secret != ""
        else token.oauth_token_secret == ""
      default: false
    }
  }

  /**
   * Not part of OAuth protocol: generate a verified token.
   * This token remains valid for one day. The consumer key and secret are optional,
   * but should be added if the token is destined to be used by a specific consumer.
   */
  function make_verified_token() {
    oauth_token = new_token()
    oauth_token_secret = ""
    oauth_verifier = ""
    oauth_callback = "oob"
    expires = Date.now() |> Date.advance(_, Duration.days(1))
    /tokens/access_tokens[oauth_token == oauth_token] <- ~{oauth_token, oauth_token_secret, oauth_verifier, oauth_callback, expires}
    oauth_token // Return only the oauth token.
  }

}
