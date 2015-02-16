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


module SearchQuery {

    private value_parse =
      parser {
      case "\"" v=((!"\"".)+) "\"":v
      case v=((!("\""|" ").)+):v
      }

    private field_value_parse =
      parser {
      case field=((!(":"|" ").)+) ":" value=value_parse : (Text.to_string(field), Text.to_string(value))
      }

    private item_parse =
      parser {
      case r=field_value_parse  : r
      case r=value_parse    : ("", Text.to_string(r))
      }

    private query_parse =
      parser{
      case item=item_parse (" "*) l=query_parse : [item | l]
      case item=item_parse (" "*)               : [item]
      }

    private function fold((key,value),aux) {
        match(key){
        case "date":  { aux with date : "{aux.date} \"{value}\"" }
        case "subject":  { aux with subject : "{aux.subject} \"{value}\"" }
        case "from":  { aux with from : "{aux.from} \"{value}\"" }
        case "cc":  { aux with from : "{aux.from} \"{value}\"" }
        case "bcc":  { aux with bcc : "{aux.bcc} \"{value}\"" }
        case "content":  { aux with content : "{aux.content} \"{value}\"" }
        case "file":  { aux with file : "{aux.file} \"{value}\"" }
        case "filename":  { aux with filename : "{aux.filename} \"{value}\"" }
        case "type":  { aux with content_type : "{aux.content_type} \"{value}\"" }
        case "first_name":  { aux with first_name : "{aux.first_name} \"{value}\"" }
        case "last_name":  { aux with last_name : "{aux.last_name} \"{value}\"" }
        case "email":  { aux with email : "{aux.email} \"{value}\"" }
        case "status":  { aux with status : "{aux.status} \"{value}\"" }
        case "teams":  { aux with teams : "{aux.teams} \"{value}\"" }
        case "sgn":  { aux with sgn : "{aux.sgn} \"{value}\"" }
        case "name":  { aux with name : "{aux.name} \"{value}\"" }
        case "nickname":  { aux with nickname : "{aux.nickname} \"{value}\"" }
        case "displayName":  { aux with displayName : "{aux.displayName} \"{value}\"" }
        case "": { aux with any : "{aux.any} \"{value}\"" }
        default: { aux with unexpected : [key|aux.unexpected]}
        }
    }

    function parse(string query) {
        l = Option.default([],Parser.try_parse(query_parse,query))
      init = { subject:"", from:"", cc:"", bcc:"", file:"", // emails
               filename:"", content_type:"", // files
               first_name:"", last_name:"", email:"", status:"", teams:"", sgn:"", // users
               name:"", nickname:"", displayName:"", // contacts
               content:"", date:"", // common
               any:"", unexpected:[], in:"", owner:""
             }
        List.fold(fold,l,init)
    }

    function to_string(what, query) {
      function print(key,value) { if (value != "") ["{key}:{value}"] else [] }
      l =
        match (what) {
        case {emails}:
          List.flatten([
            print("subject",query.subject),
            print("from",query.from),
            print("cc",query.cc),
            print("bcc",query.bcc),
            print("file",query.file),
            print("content",query.content),
            print("date",query.date),
            print("in",query.in),
            if (query.any == "") [] else [query.any]
          ])
        case {files}:
          List.flatten([
            print("filename",query.filename),
            print("content_type",query.content_type),
            print("content",query.content),
            print("date",query.date),
            if (query.any == "") [] else [query.any]
          ])
        case {users}:
          List.flatten([
            print("first_name",query.first_name),
            print("last_name",query.last_name),
            print("email",query.email),
            print("status",query.status),
            print("teams",query.teams),
            print("sgn",query.sgn),
            if (query.any == "") [] else [query.any]
          ])
        case {contacts}:
          List.flatten([
            print("email",query.email),
            print("name",query.name),
            print("nickname",query.nickname),
            print("displayName",query.displayName),
            print("owner",query.owner),
            if (query.any == "") [] else [query.any]
          ])
        }
      List.to_string_using("",""," ",l)
    }

}
