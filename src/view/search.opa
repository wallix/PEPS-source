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


package com.mlstate.webmail.view

module SearchView {

  private function log(msg) { Log.notice("[SearchView]", msg) }

  client function search_callback(Mode.t mode, query, res) {
    match (res) {
      case {failure: msg}: Notifications.error(AppText.search(), <>{msg}</>)
      case {success: html}:
        match (mode) {
          case {messages: _}: Dom.transform([#messages_list = html])
          case {files: _}:
            Dom.transform([
              #files_list = html,
              #search_notice = "{@i18n("File search")}: \"{query}\""
            ])
            Dom.hide(#files_breadcrumb)
            Dom.show(#search_notice)
          case {people: "users"}: Dom.transform([#users_main = html])
          case {people: "contacts"}: Dom.transform([#contacts_list = html])
          default: void
        }
    }
  }

  protected function server_search_callback(mode, state, box, query, res) {
    match (res) {
      case {success: messages}:
        html = MessageView.Panel.build(state, {some: box}, Message.make_page(messages), some(query), none)
        search_callback(mode, "", {success: html})
      case {failure: msg}: search_callback(mode, "", {failure: msg})
    }
  }

  protected function server_file_search_callback(anchor_type, path, state, query, res) {
    match (res) {
      case {success: files}:
        match (Directory.get_from_path(state.key, {none}, path)) {
          case ~{dir}:
            (sfiles, files, directories) =
              if (query == "") {
                files = FileToken.list(state.key, dir, {user}, true)
                directories = Directory.list(state.key, dir, {user})
                (none, files, directories)
              } else
                ({some: files}, [], [])
            html = DirectoryView.build(state.key, [], directories, files, false, none, sfiles)
            search_callback(anchor_type, query, {success: html})
          default: search_callback(anchor_type, "", {failure: AppText.non_existent_folder(path)})
        }
      case {failure: msg} -> search_callback(anchor_type, "", {failure: msg})
    }
  }

  protected function server_user_search_callback(mode, state, query, res) {
    match (res) {
      case {success: users}:
        html = UserView.build_page(state, UserController.page(users), {some: query}, User.emptyFilter)
        search_callback(mode, query, {success: html})
      case {failure: msg}: search_callback(mode, "", {failure: msg})
    }
  }

  protected function server_contact_search_callback(anchor_type, state, query, res) {
    match (res) {
      case {success: contacts}:
        html = ContactView.build_contacts(contacts, false /* Display contacts, not users*/)
        search_callback(anchor_type, query, {success: html})
      case {failure: msg}: search_callback(anchor_type, "", {failure: msg})
    }
  }

  exposed @async function do_server_search(URN.t urn, string query) {
    mode = urn.mode
    path = urn.path
    state = Login.get_state() // Login is checked at controller level.
    // TODO: also check the path in cases such as {people} and {admin}.
    match (mode) {
      case {messages: box}:      SearchController.search(state, box, query, server_search_callback(mode, state, box, query, _))
      case {files: _}:           SearchController.search_files(state, query, server_file_search_callback(mode, path, state, query, _))
      case {people: "users"}:    SearchController.search_users(state, query, server_user_search_callback(mode, state, query, _))
      case {people: "contacts"}: SearchController.search_contacts(state, query, server_contact_search_callback(mode, state, query, _))
      default:                   Notifications.error(AppText.search(), <>{@i18n("No search for {Mode.name(mode)} implemented yet")}</>)
    }
  }

  client function search(_evt) {
    query = Dom.get_value(#search_input)
    urn = URN.get()
    if (String.is_empty(query)) Content.refresh()
    else do_server_search(urn, query)
  }

  client function blur(_evt) { Dom.give_blur(#search_input) }
  client function hide(_evt) { Modal.hide(#search_info) }
  client function show(_evt) { Modal.show(#search_info) }

  client function focus(_evt) {
    if (Dom.is_empty(#search_input))
      Dom.give_focus(#loginbox_username)
    else {
      Dom.give_focus(#search_input)
      Dom.select(#search_input)
    }
  }

  /** Clear search results. */
  client function clear(evt) {
    Dom.set_value(#search_input, "")
    Dom.remove(#clear_query)
    search(evt)
  }

  /** Insert the clear icon. */
  client function insert_clear(_evt) {
    query = Dom.get_value(#search_input)
    if (query == "") Dom.remove(#clear_query) |> ignore
    else if (Dom.is_empty(#clear_query))
      Dom.put_after(
        #search_input,
        Dom.of_xhtml(<span id="clear_query" class="fa fa-close-o" title="{@i18n("Clear query")}" onclick={clear}></span>)
      ) |> ignore
  }

  protected function build_form(Login.state state) {
    Modal.make(
      "search_info",
      <> {@i18n("Some hints about search")} : </>,
      <>
        <div> {@i18n("The search will be performed on the current box only, and only for already fetched emails.")}</div><br>
        <div><span class="search_info_label"> {@i18n("hello")} </span> : {@i18n("search for all mails containing 'hello' or any word that contains 'hello'")}</div>
        <div><span class="search_info_label"> {"\"{@i18n("hello")}\""} </span> : {@i18n("search for all mails containing the word 'hello'")}</div><br>
        <div> {@i18n("To combine several words, use space as OR, and symbol '+' as AND")} </div><br>
        <div><span class="search_info_label"> {@i18n("hello world")} </span> : {@i18n("search for all mails containing either 'hello' OR 'world', or any word that contains 'hello' or 'world'")}</div>
        <div><span class="search_info_label"> {@i18n("hello + world")} </span> : {@i18n("search for all mails containing both 'hello' AND 'world', or any word that contains 'hello' or 'world '")}</div>
        <div><span class="search_info_label"> {@i18n("hello + world  again")}</span> : {@i18n("search for all mails containing both 'hello' AND 'world' OR 'again', or any word that contains 'hello', 'world ' or 'again'")}</div>
      </>,
      WB.Button.make({button: <>OK</>, callback: hide}, []),
      Modal.default_options
    )
  }

  protected function build(Login.state state) {
    if (not(Login.is_logged(state))) <></>
    else
      <form id=#search role="search" class="navbar-form" method="post" action="javascript:void(0)">
        <div class="form-group">
          <input type="text" id=#search_input class="form-control"
              placeholder="{AppText.search()}"
              onnewline={search}
              onkeyesc={blur}
              oninput={insert_clear}/>
        </div>
      </form>
}}
