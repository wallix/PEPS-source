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

solr_options = {
  domain : AppParameters.parameters.solr_addr,
  port : AppParameters.parameters.solr_port,
  collection : "peps_mail"
}

SolrMessage = Solr(solr_options)
SolrFile = Solr({solr_options with collection : "peps_file"} )
SolrUser = Solr({solr_options with collection : "peps_user"} )
SolrContact = Solr({solr_options with collection : "peps_contact"} )

type Search.kind =
  {messages} or
  {files} or
  {users} or
  {contacts}

module Search {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[Search]", msg) }
  private function error(msg) { Log.error("[Search]", msg) }

  private date_printer = Date.generate_printer("%Y-%m-%dT%H:%M:%SZ")

  private highlighting_pre = "<em class=\"k\">"
  private highlighting_pre_escaped = Xhtml.escape_special_chars(highlighting_pre)
  private highlighting_post = "</em>"
  private highlighting_post_escaped = Xhtml.escape_special_chars(highlighting_post)

  function highlighted_to_xhtml(s) {
      s
    |> Xhtml.escape_special_chars
    |> String.replace(highlighting_pre_escaped, highlighting_pre, _)
    |> String.replace(highlighting_post_escaped, highlighting_post, _)
    |> Xhtml.of_string_unsafe
  }

  private function emph(s) {
    s = String.replace("%{highlighting_pre}", "{highlighting_pre}%", s)
    String.replace("{highlighting_post}{highlighting_pre}","",s)
  }
  private function decode(s) { UrlEncoding.decode(emph(s)) }
  private function render(l) {
    match (List.map(decode, l)) {
      case [frag]: frag
      default : List.to_string_using("<ul><li>", "...</li><li><strong>...</strong></li></ul>", "...</li><li>", l)
    }
  }

  /** General query options. */
  queryoptions = { SolrMessage.default_query_options with
    highlight : ["subject", "content"],
    highlight_snippets : 4,
    highlight_html : { pre : highlighting_pre, post : highlighting_post }
  }

  /** Global operations and search selection. */

  module All {

    exposed @async function void reindex(Search.kind kind, progress, callback) {
      match (kind) {
        case {messages}: Search.Message.reindex(progress)
        case {files}: Search.File.reextract(progress)
        case {users}: Search.User.reindex(progress)
        case {contacts}: Search.Contact.reindex(progress)
      }
      callback()
    }

    exposed @async function void clear(Search.kind kind, callback) {
      match (kind) {
        case {messages}: Search.Message.clear()
        case {files}: Search.File.clear()
        case {users}: Search.User.clear()
        case {contacts}: Search.Contact.clear()
      } |> ignore
      callback()
    }

  } // END ALL


  /** {1} Message indexing. */

  module Message {

    /** Query options. */
    private options = queryoptions

    /** Transform a message into an indexable object. */
    private function indexable(User.key key, Message.header header, list(User.key) owners, string content) {
      // TODO: real plain text.
      ioml = List.map(@toplevel.Message.Address.to_string, _)
      { id: header.id,
        from: @toplevel.Message.Address.to_string(header.from),
        to: ioml(header.to),
        cc: ioml(header.cc),
        bcc: ioml(header.bcc),
        subject: UrlEncoding.encode(header.subject),
        content: UrlEncoding.encode(content),
        date: Date.to_formatted_string(date_printer, header.created),
        in: owners,
        owner: key }
    }

    /** Index a split message. */
    private function index2(key, Message.header header, list(User.key) owners, string content) {
      log("Message: indexing message [{header.id}]")
      iom = indexable(key, header, owners, content)
      // case {none}: {success:@intl("message {message.id} did not need to be indexed")};
      match (SolrMessage.index(iom)) {
        case ~{success}: ~{success}
        case ~{failure}:
          SolrJournal.add_index(iom)
          ~{failure}
      }
    }

    /** Index a message. */
    function index(key, Message.full message) {
      index2(key, message.header, message.owners, message.content)
    }

    /** Remove an indexable from solr. */
    private function delete(string id, string owner) {
      match (SolrMessage.delete([("id",id)])) {
        case ~{success}: ~{success}
        case ~{failure}:
          SolrJournal.remove_index(id, owner)
          ~{failure}
      }
    }

    /** Clear the full message index. */
    function clear() {
      SolrJournal.clear_index()
      SolrMessage.delete([("*","*")])
    }

    /** Unindex a message for a specific user. */
    function unindex(string id, string owner) {
      match (SolrMessage.unhighlighted_query("id:{id}", SolrMessage.default_query_options)) {
        case {success: []}: delete(id, owner)
        case {success: list}:
          mails = List.filter_map(unserialize, list)
          List.fold(function (mail, res) {
            match (res) {
              case {success}:
                if (mail.in == [] || mail.in == [owner])
                  delete(id, owner)
                else {
                  in = List.filter(function (o) { o != owner }, mail.in)
                  mail = {mail with ~in}
                  match (SolrMessage.index(mail)) {
                    case {success:_}: {success}
                    case {~failure}: ~{failure}
                  }
                }
              case ~{failure}: ~{failure}
            }
          }, mails, {success})

        case ~{failure}:
          SolrJournal.remove_index(id, owner)
          ~{failure}
      }
    }

    /** Force the reindexing of all messages. */
    function reindex((int -> void) progress) {
      match (clear()) {
        case {success: _}:
          total = @toplevel.Message.count()
          Iter.fold(function (message, (i, previous)) {
            owners =
              @toplevel.Message.Address.keys([message.from]) ++
              @toplevel.Message.Address.keys(message.to) ++
              @toplevel.Message.Address.keys(message.cc) ++
              @toplevel.Message.Address.keys(message.bcc)
            content = @toplevel.Message.get_content(message.id)
            index2(message.creator, message, owners, content) |> ignore
            current = (i*100)/total
            if (current != previous) progress(current)
            (i+1, current)
          }, @toplevel.Message.all(), (1,1)) |> ignore
      case {~failure}:
        error("Message.reindex: {@intl("failed to remove Solr index")} {failure}");
      }
    }

    /**
     * Query messages from the Solr server.
     * The results are fetched from the database, and formatted with highlightings.
     */
    function search(User.key key, Mail.box mbox, string query) {
      // TODO: use solr offset and start options for result paging (currently limited to the first 10 results)
      // TODO: catch and handle solr exceptions
      if (query == "") {success: []}
      else {
        query = SearchQuery.parse(UrlEncoding.encode(query))
        // Add user teams to query.
        qowners =
          teams = @toplevel.User.get_teams(key)
          if (teams == []) "{key}"
          else "({String.concat(" OR ", [key|teams])})"
        // TODO: handle unexpected fields reported in query.unexpected
        // TODO: another mail query with empty content and empty any + merged via db with file query result
        mquery = { query with in : qowners } |> SearchQuery.to_string({emails},_)
        fquery = { query with in : "" } |> SearchQuery.to_string({files},_)
        match (SolrMessage.query(mquery, options)) {
          case {success: mresult}:
            match (SolrFile.query(fquery, options)) { // TODO: remove mail specific fields from the query
              case {success: fresult}:
                function l2map(r) { StringMap.From.assoc_list(r.highlightings) }
                mail_highlightings = l2map(mresult)
                file_highlightings = l2map(fresult)
                match (mresult.get("id")) {
                  case {success: ids}:
                    mids = List.map(@toplevel.Message.sofmid, ids)
                    match (fresult.get("id")) {
                      case {success: fids}:
                        {success: fetch(mids, fids, key, mbox, mail_highlightings, file_highlightings)}
                      case ~{failure}: ~{failure}
                    }
                  case ~{failure}: ~{failure}
                }
              case ~{failure}: ~{failure}
            }
          case ~{failure}: ~{failure}
        }
      }
    }

    /** Convert the raw json result to an indexable. */
    function unserialize(RPC.Json.json raw) {
      match (raw) {
        case {Record: record}:
          (su, id, co, in, obj) =
            List.fold(function ((string, RPC.Json.json) f, (su, id, co, in, obj)) {
              match (f) {
                case ("subject", {String: subject}): (true, id, co, in, {obj with ~subject})
                case ("id", {String: id}): (su, true, co, in, {obj with ~id})
                case ("content", {String: content}): (su, id, true, in, {obj with ~content})
                //case ("_version_",{Int:_version_}): {acc with ~_version_};
                case ("in", {List: l}):
                  in = List.filter_map(function (s) { match (s) { case {String: s}: some(s) ; default: none } }, l)
                  (su, id, co, true, {obj with ~in})
                default: (su, id, co, in, obj)
              }
            }, record, (false, false, false, false, {subject: "", id: "", content: "", in: []}))
          // Return the value iff all fields present.
          if (su && id && co && in) some(obj) else none
        default: none
      }
    }

    /** Highlight the search results. */
    private function highlight(message, mail_highlightings, file_highlightings) {
      // Highlighted subjects and content.
      (subject, content) =
        match (StringMap.get(@toplevel.Message.sofmid(message.id), mail_highlightings)) {
          case {some: fields}:
            List.fold(function ((field, value), (subject, content)) {
              match (field) {
                case "subject": (some(render(value)), content)
                case "content": (subject, some(render(value)))
                default: (subject, content)
              }
            }, fields, (none,none))
          default: (none, none)
        }
      // Highlighted files.
      files = List.fold(function (fid, highlights) {
        match (StringMap.get(fid, file_highlightings)) {
          case {some: fields} :
            List.fold(function((field, value), highlights) {
              match (field) {
                case "content":
                  // TODO: this is for testing purpose (it will be properly done with postgres joins)
                  filename = @toplevel.File.getName(fid) ? "mongo.pdf"
                  ["<strong>{filename}</strong>{render(value)}" | highlights]
                default: highlights
              }
            }, fields, highlights)
          default: highlights
        }
      }, List.map(@toplevel.File.sofid, message.files), [])

      @toplevel.Message.highlight(message, subject, content, files)
    }

    /** Fetch the search results from the database, and add the highlightings. */
    private function fetch(mids, fids, key, mbox, mail_highlightings, file_highlightings) {
      @toplevel.Message.search(mids, fids, key, mbox) |> Iter.to_list |>
      List.map(highlight(_, mail_highlightings, file_highlightings), _)
    }

    /**
     * Asynchronous indexation. This is particularly important for API functions, since we don't want to
     * lose time waiting for the indexation to be done.
     */
    module Async {
      @async protected function index(key, message, ('a -> void) callback) { Message.index(key, message) |> callback }
    }

  } // END MESSAGE


  /** {1} User indexing. */

  module User {

    /** Query options. */
    private options = { queryoptions with
      highlight : ["first_name", "last_name", "sgn"],
      highlight_snippets : 4,
      highlight_html : { pre : highlighting_pre, post : highlighting_post }
    }

    /** Transform a user into an indexable object. */
    private function indexable(User.t user) {
      { id: user.key,
        first_name: UrlEncoding.encode(user.first_name),
        last_name: UrlEncoding.encode(user.last_name),
        email: Email.to_string(user.email),
        status: @toplevel.User.status_to_string(user.status),
        level: user.level,
        teams: user.teams,
        sgn: UrlEncoding.encode(user.sgn) }
    }

    /** Index a user. */
    function index(User.t user) {
      indexable = indexable(user)
      match (SolrUser.index(indexable)) {
        case ~{success}: ~{success}
        case ~{failure}:
          SolrJournal.add_census(indexable)
          ~{failure}
      }
    }

    /** Recompute the full user index. */
    function reindex((int -> void) progress) {
    match (clear()) {
      case {success: _}:
        total = @toplevel.User.count([])
        Iter.fold(function (user, (i, previous)) {
          index(user) |> ignore
          current = (i*100)/total
          if (current != previous) progress(current)
          (i+1, current)
        }, @toplevel.User.iterator(), (1, 1)) |> ignore
      case ~{failure}:
        error("User.reindex: {@intl("failed to remove Solr user")} {failure}");
    }
  }

    /** Delete the index associated with a user. */
    function delete(string id) {
      match (SolrUser.delete([("id",id)])) {
        case ~{success}: ~{success}
        case ~{failure}:
          SolrJournal.remove_census(id)
          ~{failure}
      }
    }

    /** Clear the full user index. */
    function clear() {
      SolrJournal.clear_census()
      SolrUser.delete([("*","*")])
    }

    /** Add highlightings to a user. */
    private function highlight(user, highlightings) {
      match (StringMap.get(user.key, highlightings)) {
        case {some: l}:
          (hfname, hlname, hsgn) = List.fold(function ((field, value), (fn, ln, sg)) {
            match (field) {
              case "first_name": (some(render(value)), ln, sg)
              case "last_name": (fn, some(render(value)), sg)
              case "sgn": (fn, ln, some(render(value)))
              default: (fn, ln, sg)
            }
          }, l, (none, none, none))
          @toplevel.User.highlight(user, hfname, hlname, hsgn)
        default:
          @toplevel.User.highlight(user, none, none, none)
      }
    }

    /** Fetch and highlight the search results. */
    private function fetch(uids, highlightings) {
      @toplevel.User.iterator_in(uids) |>
      Iter.map(highlight(_, highlightings), _) |>
      Iter.to_list
    }

    /** Send a query and fetch the result users. */
    function search(string query) {
      if (query == "")
        {success: []}
      else {
        query = SearchQuery.to_string({users}, SearchQuery.parse(query))
        match (SolrUser.query(query, options)) {
          case {success: results}:
            function l2map(r) { StringMap.From.assoc_list(r.highlightings) }
            highlightings = l2map(results)
            match (results.get("id")) {
              case {success: uids}: {success: fetch(uids, highlightings)}
              case ~{failure}: ~{failure}
            }
          case ~{failure}: ~{failure}
        }
      }
    }

  } // END USER

  /** {1} File indexing. */

  module File {

    /** Query options. */
    private options = { queryoptions with
      fields : ["id"],
      highlight : ["content"]
    }

    /** Index a file in Solr. */
    function extract(RawFile.id id, binary content, string name, string mimetype) {
      addfields = [("filename", name)]
      match (SolrFile.extract(id, content, mimetype, addfields)) {
        case ~{success}: ~{success}
        case ~{failure}:
          SolrJournal.add_extract(id, name, mimetype)
          ~{failure}
      }
    }

    /** Remove a file index. */
    function unextract(RawFile.id id) {
      match (SolrFile.delete([("id", id)])) {
        case ~{success}: ~{success}
        case ~{failure}:
          SolrJournal.remove_extract(id)
          ~{failure}
      }
    }

    /** Clear the full file index. */
    function clear() {
      SolrJournal.clear_extract()
      SolrFile.delete([("*","*")])
    }

    /** Rebuild the full index. */
    function reextract((int -> void) progress) {
      match (clear()) {
        case {success: _}:
          total = @toplevel.File.count(none)
          Iter.fold(function (File.t file, (i, previous)) {
            // Note: rather than looping over raw files, just index the files that effectively correspond to
            // a file, to minimize the number of indexed raws.
            match (RawFile.get(file.published)) {
              case {some: raw}:
                extract(raw.id, RawFile.getBytes(raw), raw.name, raw.mimetype) |> ignore
                current = (i*100)/total
                if (current != previous) progress(current)
                (i+1, current)
              case {none}:
                error(@intl("File.reextract: missing file {file.published}"))
                (i+1, previous)
            }
          }, @toplevel.File.iterator(), (1, 1)) |> ignore
        case ~{failure}:
          error("File.reextract: {@intl("failed to remove Solr index")} {failure}")
      }
    }

    /** Add the highlighted portions of a file content to the client file token. */
    private function highlight(token, highlightings) {
      match (StringMap.get(RawFile.sofid(token.active), highlightings)) {
        case {some: l}:
          content = List.fold(function ((field, value), content) {
            match (field) {
              case "content": some(render(value))
              default: content
            }
          }, l, none)
          FileToken.highlight(token, content)
        default: FileToken.highlight(token, none)
      }
    }

    /** Fetch the search results. */
    private function fetch(User.key owner, rawids, highlightings) {
      FileToken.search(owner, rawids) |>
      Iter.fold(function (token, tokens) {
        [highlight(token, highlightings) | tokens]
      }, _, [])
    }

    /** Send a search query, then fetch and format the results. */
    function search(User.key owner, string query) {
      if (query == "")
        {success: []}
      else {
        query = SearchQuery.parse(query) |> SearchQuery.to_string({files}, _)
        match (SolrFile.query(query, options)) {
          case {success: results}:
            function l2map(r) { StringMap.From.assoc_list(r.highlightings) }
            highlightings = l2map(results)
            match (results.get("id")) {
              case {success: rawids}:
                {success: fetch(owner, rawids, highlightings)}
              case ~{failure}: ~{failure}
            }
          case ~{failure}: ~{failure}
        }
      }
    }

  } // END FILE

  /** {1} Contact indexing. */

  module Contact {

    /** SOLR options. */
    private options = { queryoptions with
      // Field 'id' is already asked for in in mail_query_options.
      highlight : ["emails", "nickname", "displayName"],
      highlight_snippets : 4,
      highlight_html : { pre : highlighting_pre, post : highlighting_post }
    }

    /** Convert a PEPS contact to an indexable object. */
    private function indexable(Contact.t contact) {
     ~{ id: contact.id,
        emails: List.map(function (item) { Email.address_to_string(item.elt) }, contact.info.emails),
        owner: contact.owner,
        displayName: UrlEncoding.encode(contact.info.displayName),
        //name:UrlEncoding.encode(contact.info.name.formatted), // TODO: email_name:...
        //name: UrlEncoding.encode(contact.info.name),
        nickname: UrlEncoding.encode(contact.info.nickname),
        blocked: if (contact.status=={blocked}) "t" else "f" }
    }

    /** Index a new contact. */
    function index(Contact.t contact) {
      obj = indexable(contact)
      match (SolrContact.index(obj)) {
        case ~{success}: ~{success}
        case ~{failure}:
          SolrJournal.add_book(obj)
          ~{failure}
      }
    }

    /** Remove an indexed contact. */
    function unindex(string owner, Email.email email) {
      match (SolrContact.delete([("emails", Email.to_string_only_address(email)),("owner",owner)])) {
        case ~{success}: ~{success}
        case ~{failure}:
          SolrJournal.remove_book(owner, Email.to_string_only_address(email))
          ~{failure}
      }
    }

    /** Add highlightings to the search results. */
    private function hightlight(Contact.t contact, highlightings) {
      function emph(xs) {
        xs = List.map(function (x) { UrlEncoding.decode(emph(x)) }, xs)
        match (xs) {
          case [x]: x
          default: List.to_string_using("<ul><li>", "...</li><li><strong>...</strong></li></ul>", "...</li><li>", xs)
        }
      }
      cc = @toplevel.Contact.to_client_contact(contact)
      match (StringMap.get(contact.id, highlightings)) {
        case {none}: cc
        case {some: l}:
          (highlighted_emails, highlighted_name, highlighted_displayName) =
            List.fold(
              function ((field, value), (emails, nickname, displayname)) {
                match (field) {
                  case "emails": (some(emph(value)), nickname, displayname)
                  case "nickname": (emails, some(emph(value)), displayname)
                  case "displayName": (emails, nickname, some(emph(value)))
                  default: (emails, nickname, displayname)
                }
              }, l, (none, none, none))
          ~{cc with highlighted_emails, highlighted_name, highlighted_displayName}
      }
    }

    private function list(Contact.client_contact) fetch(key, list(Contact.id) ids, highlightings) {
      Iter.fold(function (contact, results) {
        contact = hightlight(contact, highlightings)
        [contact|results]
      }, @toplevel.Contact.iterator(ids), [])
    }

    /** Solr search amongst indexed contacts. */
    function search(User.key owner, string query) {
      if (query == "") {success: []}
      else {
        query = SearchQuery.to_string({contacts}, {SearchQuery.parse(query) with ~owner})
        match (SolrContact.query(query, options)) {
          case {success: result}:
            // Retrieve the id of searched contacts.
            match (result.get("id")) {
              case {success: contacts}:
                highlightings = StringMap.From.assoc_list(result.highlightings)
                {success: fetch(owner, contacts, highlightings)}
              case ~{failure}: ~{failure}
            }
          case ~{failure}: ~{failure}
        }
      }
    }

    /** Remove all indexed contacts. */
    function clear() {
      SolrJournal.clear_book()
      SolrContact.delete([("*","*")])
    }

    /** Rebuild the index. */
    function reindex((int -> void) progress) {
      match (clear()) {
        case {success: _}:
          total = @toplevel.Contact.count()
          contacts = DbSet.iterator(/webmail/addrbook/contacts)
          Iter.fold(function (contact, (i,lp,v)) {
            index(contact) |> ignore
            prog = (i*100) / total
            (i+1, prog, if (prog != lp) progress(prog))
          }, contacts, (1, 1, void)).f3

        case ~{failure}:
          error("Contact.reindex: {@intl("failed to remove Solr contact")} {failure}")
      }
    }

  } // END CONTACT

  /** ??? */
  function finalize_index() { void }

} // END SEARCH
