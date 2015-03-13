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

module FolderView {

  /** {1} Log */

  private function log(msg) { Log.notice("FolderView:", msg) }
  private function warning(msg) { Log.warning("FolderView:", msg) }
  private function debug(msg) { Log.debug("FolderView:", msg) }
  private function error(msg) { Log.error("FolderView:", msg) }

  /** {1} Creation */

  create_callback = function {
    case {success: html}:
      Utils.client_transform(Dom.put_replace, #modal_folder, html) |> ignore
      Modal.show(#modal_folder)
      Scheduler.sleep(500, function () { Dom.give_focus(#folder_name) })

    case {failure: e}:
      Notifications.error(@i18n("Folder creation"), <>{e}</>)
  }

  @async
  exposed function do_create(Dom.event _evt) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      create_callback({failure: Content.login_please})
    else {
      html = build_form(state, none)
      create_callback({success: html})
    }
  }

  /** {1} Edition */

  @async
  edit_callback = function {
    case {success: html}:
      Utils.client_transform(Dom.put_replace, #modal_folder, html) |> ignore
      Modal.show(#modal_folder)
      Scheduler.sleep(500, function () { Dom.give_focus(#folder_name) })
    case {failure: e}: void
  }

  @async
  exposed function edit(Folder.id id) {
    state = Login.get_state()
    match (Folder.get(state.key, id)) {
      case {none}:
        edit_callback({failure: @i18n("Folder not found")})
      case {some: folder}:
        html = build_form(state, some(folder))
        edit_callback({success: html})
    }
  }

  function do_edit(Folder.id id, _evt) { edit(id) }

  /** {1} Deletion */

  delete_callback = function {
    case {success}:
      Scheduler.sleep(1000, function () { refresh() })
    case {failure: e}:
      Notifications.error(@i18n("Delete failure"), <>{e}</>)
  }

  /**
   * TODO: give the user the possibilty to choose the destination box of the mails
   * previously in {id}.
   */
  @async
  exposed function delete(Folder.id id, string name) {
    if (Client.confirm(@i18n("Are you sure you want to delete the folder {name}?")))
      FolderController.Async.delete(id, {inbox}, delete_callback)
    else void
  }

  function do_delete(Folder.id id, string name, _evt) {
    delete(id, name)
  }

  /** {1} Update */

  save_callback = function {
    case {success: id}:
      Modal.hide(#modal_folder)
      refresh()
    case {failure: e}:
      Notifications.error(AppText.Save_failure(), <>{e}</>)
  }

  @async
  exposed function save(option(Folder.id) id, string name) {
    FolderController.Async.save(id, name, save_callback)
  }

  function do_save(option(Folder.id) id, Dom.event _evt) {
    name = Dom.get_value(#folder_name)
    log("Entered name: {name}")
    save(id, name)
  }

  function do_cancel(Dom.event _evt) {
    Modal.hide(#modal_folder)
  }

  /** {1} Display: folder edition */

  protected function build_folders() {
    state = Login.get_state()
    folders =
      Folder.list(state.key) |>
      List.filter(function (folder) { not(Folder.is_system(folder.id)) }, _)

    list = List.fold(function (folder, acc) {
      text = if (folder.content.unread == 0) "{folder.name}" else "{folder.name} ({folder.content.unread})"
      sname = Uri.encode_string(folder.name) // Sanitized name.
      href = "folder/{sname}"
      (<><div class="pull-right">
        <span class="fa fa-minus-circle-o" title="{AppText.delete()}" rel="tooltip" data-placement="bottom"
            onclick={do_delete(folder.id, folder.name, _)}
            options:onclick={[{stop_propagation}]}/>
        </div>
        <span class="fa fa-lg fa-folder-o"></span> {text}
      </>, (@public_env(do_edit(folder.id, _)))) +> acc
    }, folders, [])

    ListGroup.make(list, @i18n("No folders"))
  }

  /** {1} Build */

  protected function build_form(Login.state state, option(Folder.t) folder) {
    save_text = if (Option.is_some(folder)) AppText.save() else AppText.create()
    name = Option.map(_.name, folder) ? ""
    id = Option.map(_.id, folder)

    Form.wrapper(
      <div class="form-group">
        <div class="frow">
          <label class="control-label fcol" for="folder_name">{AppText.name()}:</label>
          <div class="fcol fcol-lg">
            <input id="folder_name" type="text" class="form-control" autocomplete="off" value="" placeholder="{@i18n("Folder name")}">
          </div>
        </div>
      </div>
    , true) |>
    Modal.make(
      "modal_folder",
      <>{
        match (folder) {
          case {none}: AppText.create_folder()
          case {some: folder}: AppText.edit_folder(folder.name)
        }
      }</>, _,
      WB.Button.make({button: <>{AppText.Cancel()}</>, callback: do_cancel}, []) <+>
      WB.Button.make({button: <>{save_text}</>, callback: do_save(id, _)}, [{primary}]),
      {Modal.default_options with backdrop: false}
    )
  }

  protected function build(Login.state state) {
    if (not(Login.is_logged(state)))
      Content.login_please
    else
      <div id=#folders_list class="pane-left folders_list">
        <div class="pane-heading">
          <h3>{AppText.folders()}</>
        </div>
        {build_folders()}
      </div>
      <div id=#folder_viewer class="pane-right"/>
  }

  /**
   * {1} Display: folder list
   *
   * Used in message view.
   * TODO: create a sidebar module.
   */

  protected function build_list(Login.state state, view) {
    if (not(Login.is_logged(state))) <></>
    else {
      list =
        Folder.list(state.key) |>
        List.filter(function (folder) { not(Folder.is_system(folder.id)) }, _)

      xlist = List.fold(function (folder, acc) {
        urn = {
          mode: {messages: {custom: folder.id}},
          path: []
        }
        onclick = Content.update_callback(urn, _)
        <dt class="sidebar-menu-item"><a class="name" onclick={onclick}>
          <i class="fa fa-lg fa-folder-o"></i> {folder.name}
          <div id="{folder.id}_badge" class="badge_holder"/>
        </a></dt> <+> acc
      }, list, <></>)

      match (view) {
        case {icons}:
          if (list == []) <></>
          else
            <dl class="folders-menu">{xlist}</dl>
        case {folders}:
          xlist
        default:
          <>{@i18n("Error: view case not possible")} "{view}</>
      }
    }
  }

  @async
  exposed function refresh() {
    state = Login.get_state()
    view = SettingsController.view(state.key)
    urn = URN.get()
    if (urn.mode == {settings: "folders"})
      Dom.transform([#content = build(state)])
    else if (Mode.equiv(urn.mode, {messages: {inbox}}))
      SidebarView.refresh(state, urn)
  }

}
