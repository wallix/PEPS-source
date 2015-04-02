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


package com.mlstate.webmail.tools

type Solr.query_options = {
  list(string) fields,
  list(string) highlight,
  int highlight_snippets,
  {string pre, string post} highlight_html
}

module Solr(server_options) {

  private function error(s) {
    Log.error("[Solr]", s);
  }

  private function notice(s) {
    Log.notice("[Solr]", s);
  }

  /**
    Url and web request functions
  */

  private function uri(cmd, query) {
    Uri.uri :> { Uri.default_absolute with
      domain : server_options.domain,
      port : some(server_options.port),
      path : ["solr", server_options.collection | cmd],
      query : query
    }
  }

  private function _check_result(r, uri, to_string) {
    match(r) {
    case {success:{code:200, ~content, ... }} : {success:content};
    case {success:{~code, ~content, ... }} : {failure:@intl("server error (code {code}): {to_string(content)}")};
    case {~failure}: {failure:@intl("Fatal error connecting to {server_options.domain}:{server_options.port} ({failure})")};
    }
  }

  check_result = _check_result(_, _, identity)
  check_binary_result = _check_result(_, _, Binary.to_string)

  private function outcome(string,string) post(cmd, string content, mimetype, uri_options) {
    options = {WebClient.Post.default_options with
      content : {some:content},
      ~mimetype
    };
    uri = uri(cmd, uri_options);
    //Ansi.jlog("post: uri=%g{Uri.to_string(uri)}%d")
    //Ansi.jlog("post: content=%c{String.replace("%","percent",content)}%d")
    r = WebClient.Post.try_post_with_options(uri, options)
    check_result(r, uri)
  }

  private function outcome(binary,string) post_binary(cmd, binary content, mimetype, uri_options) {
    options = {WebClient.Post.default_binary_options with
      content : {some:content},
      ~mimetype
    };
    uri = uri(cmd, uri_options);
    r = WebClient.Post.try_post_binary_with_options(uri, options)
    check_binary_result(r, uri)
  }

  /**
    Low level JSON unserialization util functions
  */

  private function get_list(error_hint, r) {
    match (r) {
    case {List:l}: {success:l};
    default: {failure:@intl("impossible to retrieve the {error_hint} list")};
    }
  }

  private function get_string(error_hint, r) {
    match (r) {
    case {String:s}: {success:s};
    default: {failure:@intl("impossible to retrieve the {error_hint} string")};
    }
  }

  private function get_record(RPC.Json.json r) {
    match (r) {
    case {Record:l}: {success:l};
    default: {failure:@intl("unexpected server response")};
    }
  }

  private function get_field(string field_name, RPC.Json.json r) {
    match (get_record(r)) {
    case {success:l}:
      match (List.find({ function((name,_)) field_name == name }, l)) {
      case {some:(_,r)}: {success:r};
      case {none}: {failure:@intl("Field not found {field_name}")};
        //error(@intl("impossible to find the {field_name} field. Defaulting to empty string value."));
        //{success:{String:""}};
      }
    case {~failure}: {~failure};
    }
  }

  private function string_list_unserialize(r) {
    match (OpaSerialize.Json.unserialize_unsorted(r)) {
    case {some:list(string) e}: {success:e};
    default: {failure:@intl("unexpected server response")};
    }
  }

  private function unserialize(json) {
    match (Json.deserialize(json)) {
    case {some:r}: {success:r};
    case {none}: {failure:@intl("impossible to deserialized the server response")};
    }
  }

  /**
    Specific Solr response unserialization
  */


  private function get_document_list(json) {
    match (unserialize(json)) {
    case {success:r}:
      match (get_field("response", r)) {
      case {success:response}:
        match (get_field("docs",response)) {
        case {success:docs}: get_list("document", docs);
        case {~failure}: {~failure};
        }
      case {~failure}: {~failure};
      }
    case {~failure}: {~failure};
    }
  }

  private function get_result_list(document_list, field_name) {
    List.fold_backwards(function(e, res) {
                          match (res) {
                          case {success:l}:
                            match (get_field(field_name, e)) {
                            case {success:field}:
                              match (get_string(field_name, field)) {
                              case {success:s}: {success:[s|l]};
                              case {~failure}: {~failure};
                              }
                            case {~failure}: {~failure};
                            }
                          case {~failure}: {~failure};
                          }
                        }, document_list, {success:[]});
  }

  private function get_highlighting(json) {
    match (unserialize(json)) {
    case {success:r}:
      match (get_field("highlighting", r)) {
      case {success:highlighting}:
        function aux(r, next) {
          match (get_record(r)) {
          case {success:l}:
            List.fold_backwards(function ((id, r), res) {
                                  match (res) {
                                  case {success:l}:
                                    match (next(r)) {
                                    case {success:n}: {success:[(id,n)|l]};
                                    case {~failure}: {~failure};
                                    }
                                  case {~failure}: {~failure};
                                  }
                                }, l, {success:[]});
          case {~failure}: {~failure};
          }
        }
        aux(highlighting, aux(_, string_list_unserialize(_)))
      case {~failure}: {~failure};
      }
    case {~failure}: {~failure};
    }
  }

  /**
    Public and main functions
  */

  function raw_index(content) {
    options = [
      ("commit", "true")
    ]
    post(["update"], content, "application/json", options)
  }

  function _index(doc) {
    json = OpaSerialize.serialize(doc);
    content = "[{json}]"
    match (raw_index(content)) {
    case {~success}:
      //Ansi.jlog("%gIndex successful%d")
      {~success};
    case {~failure}:
      //Ansi.jlog("%rIndex failure%d")
      {~failure};
    }
  }

  function _extract(id, content, mimetype, extra_fields) {
    options = [
      ("commit", "true"),
      ("literal.id", id)
    ]
    options = options ++ List.map(
      { function((name,value)) ("literal.{name}", value) },
      extra_fields)
    post_binary(["update","extract"], content, mimetype, options)
  }

  Solr.query_options default_query_options = {
    fields : ["id"],
    highlight : ["text"],
    highlight_snippets : 1,
    highlight_html : { pre : "<em>", post : "</em>" }
  }

  function _query(query, options) {
    list_to_string = List.to_string_using("", "", ",", _)
    uri = uri(["select"], [
      // TODO: facet, start, offset
      ("q", query),
      ("wt", "json"),
      ("fl", list_to_string(options.fields)),
      ("hl", "{options.highlight != []}"),
      ("hl.fl", list_to_string(options.highlight)),
      ("hl.snippets", Int.to_string(options.highlight_snippets)),
      ("hl.simple.pre", options.highlight_html.pre),
      ("hl.simple.post", options.highlight_html.post),
    ]);
    options = WebClient.Get.default_options;
    r = WebClient.Get.try_get_with_options(uri, options)
    match (check_result(r, uri)) {
    case {success:json}:
      //Ansi.jlog("json=%c{json}%d")
      match (get_document_list(json)) {
      case {success:doc_list}:
        match (get_highlighting(json)) {
        case {success:highlightings}: {success:{get:get_result_list(doc_list,_), ~highlightings}};
        case {~failure}: {~failure};
        }
      case {~failure}: {~failure};
      }
    case {~failure}: {~failure};
    }
  }

  function _unhighlighted_query(query, options) {
    list_to_string = List.to_string_using("", "", ",", _)
    uri = uri(["select"], [("q", query), ("wt", "json")])
    options = WebClient.Get.default_options
    r = WebClient.Get.try_get_with_options(uri, options)
    match (check_result(r, uri)) {
    case {success:json}:
      match (get_document_list(json)) {
      case {success:doc_list}: {success:doc_list};
      case {~failure}: {~failure};
      }
    case {~failure}: {~failure};
    }
  }

  function _delete(fields) {
    query = String.concat("AND",List.map(function((name,value)) {"({name}:{value})"},fields))
    delete = {delete:{~query}}
    content = OpaSerialize.serialize(delete);
    options = [("commit", "true")]
    //Ansi.jlog("delete: fields=%y{fields}%d")
    //Ansi.jlog("delete: content=%g{content}%d")
    //Ansi.jlog("delete: options=%c{options}%d")
    match (post(["update"], content, "application/json", options)) {
    case {success:json}:
      match (unserialize(json)) {
      case {success:r}:
        match (get_field("responseHeader", r)) {
        case {success:responseHeader}:
          match (get_field("status", responseHeader)) {
          case {success:{Int:0}}: {success};
          case {success:{Int:status}}: {failure:@intl("Delete failed, non-zero return status {status}")};
          case {success:error}: {failure:@intl("Delete failed, {error}")};
          case {~failure}: {~failure};
          }
        case {~failure}: {~failure};
        }
      case {~failure}: {~failure};
      }
    case {~failure}: {~failure};
    }
  }

  function query(query, options) {
    @catch(function (exn) { {failure:@intl("Querying caught {exn}")} }, _query(query, options))
  }

  function unhighlighted_query(query, options) {
    @catch(function (exn) { {failure:@intl("Unhighlighted querying caught {exn}")} }, _unhighlighted_query(query, options))
  }

  function index(doc) {
    @catch(function (exn) { {failure: @intl("Indexing caught {exn}")} }, _index(doc))
  }

  function extract(id, content, mimetype, extra_fields) {
    @catch(function (exn) { {failure:@intl("Extracting caught {exn}")} }, _extract(id, content, mimetype, extra_fields))
  }

  function delete(fields) {
    @catch(function (exn) { {failure:@intl("Deleting caught {exn}")} }, _delete(fields))
  }

}
