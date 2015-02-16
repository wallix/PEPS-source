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


package com.mlstate.webmail

module Http {

	/** {1} Rules for parsing HTTP methods. */
	module Method {
	  private function rule(method) {
	    match (HttpRequest.get_method()) {
	      case {some: httpmethod}: if (httpmethod == method) Rule.succeed else Rule.fail
	      default: Rule.fail
	    }
	  }

	  @expand function post() { rule({post}) }
	  @expand function put() { rule({put}) }
	  @expand function patch() { rule({other: "patch"}) }
	  @expand function get() { rule({get}) }
	  @expand function delete() { rule({delete}) }
	  @expand function options() { rule({options}) }
} // END METHOD

	/** {1} Standard HTTP reponses. */

	function success() { Resource.raw_status({success}) }

	/** {2} Json format. */
	module Json {
	  function response(status, data) {
	    Resource.raw_response(OpaSerialize.serialize(data), "application/json", status) |>
	    Resource.add_header(_, {custom:("Access-Control-Allow-Origin", List.to_string_using("", "", " | ", AppConfig.allowed_origins))}) |>
	    Resource.add_header(_, {custom:("Access-Control-Allow-Headers", "X-Requested-With")})
	  }

	  function success(data) { response({success}, data) }
	  function not_found(data) { response({wrong_address}, data) }
	  function not_supported(v) { response({not_implemented}, {error: "API version {v} is not supported"}) }
	  function unauthorized() { response({unauthorized}, {error:AppText.Login_please()}) }
	  function forbidden(reason) { response({forbidden}, {error:reason}) }
	  function bad_request(reason) { response({bad_request}, {error:reason}) }
	  function no_content(reason) { response({no_content}, {error:reason}) }

	  /** Direct error builder. */
	  function error(err) { response(err.code, err.message) }
    /** Build a response from a standard outcome. */
    function outcome(res) {
      match (res) {
        case {success: data}: response({success}, data)
        case ~{failure}: response(failure.code, failure.message)
      }
    }
	} // END JSON

	/** {2} Form format. */
	module Form {
	  function response(status, data) {
	    Resource.raw_response(API_libs.form_urlencode(data), "application/x-www-form-urlencoded", status) |>
	    Resource.add_header(_, {custom:("Access-Control-Allow-Origin", List.to_string_using("", "", " | ", AppConfig.allowed_origins))}) |>
	    Resource.add_header(_, {custom:("Access-Control-Allow-Headers", "X-Requested-With")})
	  }

	  function success(data) { response({success}, data) }
	  function error(data) { response({internal_server_error}, data) }
} // END FORM

	/** {2} Html format. */
	module Html {
	  function error(reason) {
	    Resource.full_page(
	      AppText.app_title(),
	      <div class="alert alert-block alert-error">
	        <h4>{AppText.error()}</h4>{reason}</div>,
	      <></>,{success}, [])
	  }

	  function unauthorized() {
	    Resource.error_page(
	      AppText.Not_Allowed(),
	      Notifications.build(
	        AppText.Login_please(),
	        <>{AppText.Not_Allowed()}</>,
	        {error}
	      ),
	      {unauthorized})
	  }
	} // END HTML

	/** {1} Parsing queries. */

	module Query {
	  @expand function stringlist(string name, option(Uri.relative) uri) {
	    match (uri) {
	      case {some: uri}:
	        List.fold(function ((key, val), acc) {
	          if (key == name) [val|acc]
	          else acc
	        }, uri.query, [])
	      default: []
	    }
	  }
	  @expand function string(string name, option(Uri.relative) uri) {
	    Option.bind(function (uri) { List.assoc(name, uri.query) }, uri)
	  }

	  @expand function bool(string name, option(Uri.relative) uri) {
	    Option.bind(function (uri) { List.assoc(name, uri.query) }, uri) |>
	    Option.bind(Parser.try_parse(Rule.bool, _), _)
	  }

	  @expand function int(string name, option(Uri.relative) uri) {
	    Option.bind(function (uri) { List.assoc(name, uri.query) }, uri) |>
	    Option.bind(Parser.try_parse(Rule.integer, _), _)
	  }
	  /** NB: the binary value is expected to be in base64 encoding. */
	  @expand function binary(string name, option(Uri.relative) uri) {
      Option.bind(function (uri) { List.assoc(name, uri.query) }, uri) |>
      Option.map(Binary.of_base64, _)
    }
	} // END QUERY
}
