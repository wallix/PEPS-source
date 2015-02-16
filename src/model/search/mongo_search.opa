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

import stdlib.apis.mongo

type Mongo.textField = {string String} or {string Int} or {string Bool} or {string Double}
type Mongo.textFields = list(Mongo.textField)

type Mongo.textResult = {string String} or {int Int} or {bool Bool} or {float Double}
type Mongo.textResults = list(Mongo.textResult)

module SearchMongo {

  private H = Bson.Abbrevs

  function text(Mongo.mongodb mongodb, string dbname, string collection, string query, Bson.document filter, Mongo.textFields fields, int limit, string language) {
    function getDoc(d) { match (d.value) { case ~{Document}: some(Document) ; default: none } }
    function extract(fields, doc) {
      match (doc) {
        case [{name: "score", value: {Double: score}},
              {name: "obj", value: ~{Document}} | _]:
          results = List.filter_map(function (f) {
            match (f) {
              case {String: f}: Option.map(function (s) { {String:s} }, Bson.find_string(Document, f))
              case {Int: f}: Option.map(function (i) { {Int: i} }, Bson.find_int(Document, f))
              case {Bool: f}: Option.map(function (b) { {Bool: b} }, Bson.find_bool(Document, f))
              case {Double: f}: Option.map(function (d) { {Double: d} }, Bson.find_float(Document, f))
            }
          }, fields)
         if (List.length(fields) == List.length(results)) some((score,results)) else none
        default: none
      }
    }
    function mkflds(fields) {
      List.map(function (f) {
        match (f) {
          case {String: f}: H.i32(f, 1)
          case {Int: f}: H.i32(f, 1)
          case {Bool: f}: H.i32(f, 1)
          case {Double: f}: H.i32(f, 1)
        }
      }, fields)
    }
    params = List.flatten([
      [H.str("search", query)],
      if (limit > 0) [H.i32("limit", limit)] else [],
      if (filter != []) [H.doc("filter", filter)] else [],
      if (language != "") [H.str("language", language)] else [],
      [H.doc("project", List.append(mkflds(fields), [H.i32("_id",0)]))]
    ])
    result = MongoCommands.simple_str_command_opts(mongodb, dbname, "text", collection, params)
    match (result) {
      case {success: doc}:
        if (Bson.is_error(doc))
          {failure: {Error: Bson.string_of_doc_error(doc)}}
        else
          match (Bson.find(doc, "results")) {
            case {some: [{name: "results", value: {Array: results}}]}:
              results = List.filter_map(getDoc,results)
              results = List.filter_map(extract(fields,_), results)
              results = List.sort_by(_.f1,results)
              {success: results}
            default: {failure: {Error: "Mongo.text: {@i18n("no results field in reply")}"}}
          }
      case ~{failure}: ~{failure}
    }
  }

  private function highlight(message, _mail_highlightings, _file_highlightings, query) {
    query_words = String.explode(" ", query)
    function highlight(str) { List.fold(function (q, s) { String.replace(q, "<em>{q}</em>", s) }, query_words, str) }
    @toplevel.Message.highlight(message, some(highlight(message.subject)), none, [])
  }

  private function fetch(mids, fids, key, mbox, mail_highlightings, file_highlightings, query) {
    Message.search(mids, fids, key, mbox) |> Iter.to_list |>
    List.map(highlight(_, mail_highlightings, file_highlightings, query), _)
  }

  mongodb = Mutable.make(option(Mongo.mongodb) none)

  function void ensureOpen() {
    match (mongodb.get()) {
      case {some:_}: void
      default: mongodb.set(some(MongoConnection.openfatal("webmail")))
    }
  }

  function search(User.key key, Mail.box mbox, string query) {
    ensureOpen()
    filter = [H.doc("owners", [H.valarr("$in", [{String: key}])])]
    fields = [{String: "subject"}, {Int: "id"}]
    limit = 100
    language = "english"
    mongo = Option.get(mongodb.get())
    mids =
      match (text(mongo, "webmail", "messages", query, filter, fields, limit, language)) {
        case {success: results}:
          List.filter_map(function {
            case (_, [{String: subject}, {String: id}]): some(id)
            default: none
          }, results)
        case ~{failure}:
          Log.notice("[SearchMongo]", "search: {AppText.failure()} %r{failure}%d")
          []
      }
    fetch(mids, [], key, mbox, [], [], query)
  }

}

// TODO: logging, parse query, session

