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

module FolderController {

  /** {1} Utils */

  private function log(msg) { Log.notice("[FolderController]", msg) }
  private function warning(msg) { Log.warning("[FolderController]", msg) }
  private function debug(msg) { Log.debug("[FolderController]", msg) }
  private function error(msg) { Log.error("[FolderController]", msg) }


  /** If the folder id is none, create a new folder, else rename the given one. */
  protected function save(Login.state state, option(Folder.id) id, name) {
    debug("save: id={id} name={name}")
    issystem = Option.map(Folder.is_system, id) ? false
    if (issystem)
      {failure: @i18n("Cannot edit system folders")}
    else if (name == "")
      {failure: @i18n("Please enter a folder name")}
    else
      match (id) {
        case {some: id}:
          if (Folder.get_name(state.key, id) == {some: name})
            {success: id}
          else if (Folder.exists(state.key, name))
            {failure: @i18n("The folder [{name}] already exists")}
          else {
            // Add journal entry.
            mid = Folder.sofid(id) |> Message.midofs
            Journal.Message.log(state.key, mid, {folder: {update}}) |> ignore
            Folder.rename(state.key, id, name)
            {success: id}
          }
        default:
          if (Folder.exists(state.key, name))
            {failure: @i18n("The folder [{name}] already exists")}
          else {
            folder = Folder.create(state.key, name)
            // Add journal entry.
            mid = Folder.sofid(folder.id) |> Message.midofs
            Journal.Message.log(state.key, mid, {folder: {new}}) |> ignore
            {success: folder.id}
          }
      }
  }

  /**
   * Delete a folder.
   * @param dest destination box of all mails of box {named: id}
   */
  protected function delete(Login.state state, Folder.id id, Mail.box dest) {
    debug("delete: id={id}")
    if (Folder.is_system(id))
      {failure: @i18n("Cannot edit system folders")}
    else if (not(Folder.id_exists(state.key, id)))
      {failure: @i18n("Folder does not exist")}
    else {
      Folder.delete(state.key, id)
      box = {custom: id}
      messages = Message.all_in_mbox(state.key, box)
      Iter.iter(function (message) { MessageController.move(state, message.id, box, dest) |> ignore }, messages)
      // Add journal entry.
      mid = Folder.sofid(id) |> Message.midofs
      Journal.Message.log(state.key, mid, {folder: {delete}}) |> ignore
      {success}
    }
  }

  /** Update mail box contents following user status changes. */
  protected function update_content(User.key owner, oldstatus, newstatus) {
    function diff(old, new) {
      if (old == new) 0
      else if (new) 1
      else -1
    }
    oldid = Box.identifier(oldstatus.mbox)
    newid = Box.identifier(newstatus.mbox)
    // Condition is not strictly necessary, but avoids one db query
    // if box remains the same.
    // TODO: update 'sent' box if necessary.
    if (oldid == newid) {
      dcount = 0 // Count not changing.
      dunread = diff(newstatus.flags.read, oldstatus.flags.read)
      dstarred = diff(oldstatus.flags.starred, newstatus.flags.starred)
      dnew = diff(newstatus.opened, oldstatus.opened)
      Folder.update_content(owner, oldid, dcount, dunread, dstarred, dnew)
    } else {
      dcount = -1 // Removing one message from old box.
      dunread = if (not(oldstatus.flags.read)) -1 else 0
      dstarred = if (oldstatus.flags.starred) -1 else 0
      dnew = if (not(oldstatus.opened)) -1 else 0
      Folder.update_content(owner, oldid, dcount, dunread, dstarred, dnew)
      dcount = 1 // Adding one message to new box.
      dunread = if (not(newstatus.flags.read)) 1 else 0
      dstarred = if (newstatus.flags.starred) 1 else 0
      dnew = if (not(newstatus.opened)) 1 else 0
      Folder.update_content(owner, newid, dcount, dunread, dstarred, dnew)
    }
  }

  /**
   * Return the badegs, extracted from the folder contents.
   * @param all if all is false, only the topbar badge is returned.
   */
  protected function badges(User.key owner, bool all) {
    boxes = Folder.list(owner)
    if (all) {
      badges = {starred: 0, new: 0, badges: []}
      badges = List.fold(function (box, badges) {
        id = Folder.sofid(box.id)
        match (id) {
          case "ARCHIVE":
            { badges with
              badges: [{id: "ARCHIVE_badge", level: box.content.unread, importance: {info}}|badges.badges],
              starred: badges.starred+box.content.starred }
          case "DRAFT":
            { badges with
              badges: [{id: "DRAFT_badge", level: box.content.count, importance: {info}}|badges.badges],
              starred: badges.starred+box.content.starred }
          case "SENT": {badges with starred: badges.starred+box.content.starred}
          case "STARRED"
          case "TRASH": badges
          default:
            { badges with
              badges: [{id: "{id}_badge", level: box.content.unread, importance: {important}}|badges.badges],
              starred: badges.starred+box.content.starred,
              new: badges.new+box.content.new }
        }
      }, boxes, badges)
      // Add starred box to badges.
      { badges: [
          {id: "STARRED_badge", level: badges.starred, importance: {info}},
          {id: "messages_badge", level: badges.new, importance: {important}}| // Topbar badge.
          badges.badges
        ],
        global: badges.new,
        mode: {messages: {inbox}} }
    // Count only new messages.
    } else {
      new = List.fold(function (box, new) {
        id = Folder.sofid(box.id)
        match (id) {
          case "ARCHIVE"
          case "DRAFT"
          case "SENT"
          case "STARRED"
          case "TRASH": new
          default: new + box.content.new
        }
      }, boxes, 0)
      { badges: [{id: "messages_badge", level: new, importance: {important}}], // Topbar badge.
        global: new,
        mode: {messages: {inbox}} }
    }
  }

  /**
   * Refresh the content of each folder.
   * This function should be called once in a while to make sure
   * the counts are exact. Since every message is fetched, expect it to
   * be quite long.
   */
  protected function refresh(User.key owner) {
    log("Refresh folder contents.")
    init = {count: 0, starred: 0, unread: 0, new: 0}
    boxes = Folder.list(owner) |> List.map(function (box) { (Folder.sofid(box.id), init) }, _)
    contents = StringMap.From.assoc_list(boxes)
    messages = Message.list(owner)
    contents = Iter.fold(function (status, contents) {
      id = Box.identifier(status.mbox)
      content = StringMap.get(id, contents) ? init
      content = {content with count: content.count+1}
      content = if (not(status.flags.read)) {content with unread: content.unread+1} else content
      content = if (status.flags.starred) {content with starred: content.starred+1} else content
      content = if (not(status.opened)) {content with new: content.new+1} else content
      StringMap.add(id, content, contents)
    }, messages, contents)

    StringMap.iter(function (id, content) { Folder.set_content(owner, Folder.idofs(id), content) }, contents)
    log("Done.")
  }

  module Exposed {
    @expand function publish(method) {
      state = Login.get_state()
      if (not(Login.is_logged(state))) {failure: AppText.login_please()}
      else method(state)
    }

    exposed function save(id, name) { publish(FolderController.save(_, id, name)) }
    exposed function delete(id, dst) { publish(FolderController.delete(_, id, dst)) }
  } // END EXPOSED

  /** Asynchronous versions of the methods defined above. */
  module Async {
    @async exposed function save(id, name, ('a -> void) callback) { FolderController.Exposed.save(id, name) |> callback }
    @async exposed function delete(id, dest, ('a -> void) callback) { FolderController.Exposed.delete(id, dest) |> callback }
  }

}
