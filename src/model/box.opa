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

/** {1} Mail boxes. */

/** Predefined boxes. */
type Mail.System.box =
  {inbox} or
  {starred} or
  {archive} or
  {draft} or
  {sent} or
  {trash} or
  {spam} or
  {Date.date deleted}

/** User defined boxes. */
type Mail.User.box =
  {Folder.id custom} or // User defined box.
  {string unparsed}  // To be parsed later.

/** Predefined and user defined mail boxes. */
type Mail.box = Mail.System.box or Mail.User.box

/** Content of a mail box. */
type Mail.Box.content = {
  int count,
  int new,      // # of new, unopened messages.
  int unread,
  int starred
}

/** {1} Folders. */

/** The type of folder ids should match that of mail ids. */
type Folder.id = DbUtils.oid

type Folder.t = {
  Folder.id id,
  User.key owner,
  string name,
  option(Folder.id) parent,
  Mail.Box.content content
}

database Folder.t /webmail/folders[{id, owner}]

/** Group box printing and parsing. */
module Box {

  list(Mail.box) available   = [{inbox}, {archive}, {sent}, {trash}]
  list(Mail.box) blacklisted = [{draft}]

  /** {2} Printing. */

  /** Return the viewable name of the box. */
  name_no_i18n = function {
    case { inbox }: "inbox"
    case { starred }: "starred"
    case { archive }: "archive"
    case { draft }: "drafts"
    case { sent }: "sent"
    case { trash }: "trash"
    case { spam }: "spam"
    case { deleted: _ }: "deleted"
    case ~{ unparsed }: unparsed
    case { custom: id }: Folder.name(id) ? id
  }

  /** Return the viewable name of the box. */
  name = function {
    case { inbox }: AppText.inbox()
    case { starred }: AppText.starred()
    case { archive }: AppText.archive()
    case { draft }: AppText.drafts()
    case { sent }: AppText.sent()
    case { trash }: AppText.trash()
    case { spam }: AppText.spam()
    case { deleted: _ }: AppText.Deleted()
    case ~{ unparsed }: unparsed
    case ~{ custom }: Folder.name(custom) ? custom
  }

  /**
   * Return the identifier (label used by Gmail).
   * See this page for label names: https://developers.google.com/gmail/api/guides/labels
   */
  identifier = function {
    case { inbox }: "INBOX"
    case { starred }: "STARRED"
    case { archive }: "ARCHIVE"
    case { draft }: "DRAFT"
    case { sent }: "SENT"
    case { trash }: "TRASH"
    case { spam }: "SPAM"
    case { deleted : _ }: "DELETED"
    case ~{ unparsed }: unparsed
    case ~{ custom }: custom
  }

  /** Return the URN. */
  function print(Mail.box box) {
    match (box) {
      case { custom: id }:
        name = Folder.name(id) ? id
        "folder/{Uri.encode_string(name)}"
      case { unparsed: name }: "folder/{Uri.encode_string(name)}"
      default: name(box) |> String.lowercase
    }
  }

  /** Return the URN. */
  function print_no_i18n(Mail.box box) {
    match (box) {
      case { custom: id }:
        name = Folder.name(id) ? id
        "folder/{Uri.encode_string(name)}"
      case { unparsed: name }: "folder/{Uri.encode_string(name)}"
      default: name_no_i18n(box) |> String.lowercase
    }
  }

  /** {2} Parsing. */

  /**
   * Parse a box name.
   * TODO: implement if necessary.
   */
  function parse_name(User.key key, string name) {
    {none}
  }

  /** Parse an identifier (exclude unparsed names) */
  function iparse(string identifier) {
    match (identifier) {
      case "INBOX": {inbox}
      case "TRASH": {trash}
      // case "UNREAD": {unread}
      case "STARRED": {starred}
      case "SENT": {sent}
      case "DRAFT": {draft}
      default: {custom: identifier}
    }
  }

  /** Parse a urn mode. */
  urn_parser =
    box =
      parser {
        case "inbox" : {inbox}
        case "starred" : {starred}
        case "archive" : {archive}
        case "drafts" : {draft}
        case "sent" : {sent}
        case "trash" : {trash}
        case "spam" : {spam}
        case "folder/" name=((!"/" .)*):
          name = Text.to_string(name) |> Uri.decode_string
          {unparsed: name}
        case box=(.+):
          box = Text.to_string(box)
          if (box == AppText.inbox()) {{inbox}}
          else if (box == AppText.starred()) {{starred}}
          else if (box == AppText.archive()) {{archive}}
          else if (box == AppText.drafts()) {{draft}}
          else if (box == AppText.sent()) {{sent}}
          else if (box == AppText.trash()) {{trash}}
          else if (box == AppText.spam()) {{spam}}
          else {{inbox}} //??? is this correct
      }
    parser { case "#"? res=box: res }

  function parse_urn(User.key key, string data) {
    Parser.try_parse(urn_parser, data) |> Option.bind(parse(key, _), _)
  }

  /** Eliminate unparsed boxes. */
  function parse(User.key key, Mail.box box) {
    match (box) {
      case {unparsed: name}:
        match (Folder.find(key, name)) {
          case {some: id}: {some: {custom: id}}
          default: none
        }
      default: {some: box}
    }
  }

  /** {2} Properties. */

  /** Identify searchable mail boxes. */
  function is_searchable(User.key key, Mail.box box) {
    match (box) {
      case {inbox}: true
      case {starred}: true
      case {archive}: true
      case {draft}: false
      case {sent}:
        match (User.get_preferences(key)) {
          case {some:preferences}: preferences.search_includes_send
          case {none}: AppConfig.default_search_includes_send
        }
      case {trash}: false
      case {spam}: false
      case {deleted:_}: false
      case {custom: _}: true
      case {unparsed: _}: false
    }
  }

}

/** Folder management. */
module Folder {

  /** {1} Utils */

  private function log(msg) { Log.notice("[Folder]", msg) }
  private function warning(msg) { Log.warning("[Folder]", msg) }
  private function debug(msg) { Log.debug("[Folder]", msg) }
  private function error(msg) { Log.error("[Folder]", msg) }

  @stringifier(Folder.id) function string sofid(Folder.id id) { DbUtils.OID.sofid(id) }
  function Folder.id idofs(string s) { DbUtils.OID.idofs(s) }

  /** {1} Creation */

  /** Create a new named folder. */
  function Folder.t make(User.key owner, string name) {
    id = DbUtils.OID.gen()
    content = {count: 0, unread: 0, starred: 0, new: 0}
    ~{id, owner, name, content, parent: none}
  }

  /** Add a new folder. */
  function Folder.t create(User.key owner, string name) {
    debug("Add new folder '{name}'")
    folder = make(owner, name)
    /webmail/folders[{id: folder.id, owner: owner}] <- folder
    folder
  }

  /** Initialize the user mail system by creating folders for each pre defined mail box. */
  function init(User.key owner) {
    function init_box(Mail.box box) {
      folder = ~{
        id: Box.identifier(box),
        name: Box.name(box), owner, parent: none,
        content: {count: 0, unread: 0, starred: 0, new: 0}
      }
      /webmail/folders[{id: folder.id, owner: owner}] <- folder
    }
    List.iter(init_box, [{inbox}, {starred}, {sent}, {archive}, {draft}, {trash}])
  }


  /** {1} Modifiers */

  /** Remove all exisiting folders for a given user. */
  function void delete_all(User.key key) {
    debug("Remove all folders for user {key}")
    DbSet.iterator(/webmail/folders[owner == key].{id}) |>
    Iter.iter(function (folder) { Db.remove(@/webmail/folders[{id: folder.id, owner: key}]) }, _)
  }

  /** Delete a specific folder. */
  function void delete(User.key owner, Folder.id id) {
    debug("Delete folder {id}")
    Db.remove(@/webmail/folders[~{id, owner}])
  }

  /** Rename the given folder. */
  function rename(User.key owner, Folder.id id, string newname) {
    debug("Rename folder {id}")
    /webmail/folders[~{id, owner}]/name <- newname
  }

  /** {1} Queries */

  /**
   * Identify system folders.
   * @return [true] if the identifier is that of a system box.
   */
  function is_system(Folder.id id) {
    match (id) {
      case "INBOX"
      case "STARRED"
      case "ARCHIVE"
      case "DRAFT"
      case "SENT"
      case "TRASH"
      case "SPAM"
      case "DELETED": true
      default: false
    }
  }

  /**
   * Split a list of folder ids into different categories.
   *  - flags: unread, starred flags
   *  - folder ids
   *  - personal labels
   */
  function categorize(User.key user, list(Folder.id) ids) {
    init = { starred: false, unread: false, folders: [], labels: [], error: [] }
    List.fold(function (id, cats) {
      if (id == "STARRED") {cats with starred: true}
      else if (id == "UNREAD") {cats with unread: true}
      else if (id_exists(user, id)) {cats with folders: [Box.iparse(id)|cats.folders]}
      else
        match (Label.idofs_opt(id)) {
          case {some: lid}:
            if (Label.exists(lid)) {cats with labels: [lid|cats.labels]}
            else {cats with error: [id|cats.error]}
          default: {cats with error: [id|cats.error]}
        }
    }, ids, init)
  }

  /** List the folders owned by the given user. */
  function list(User.key key) {
    debug("list: user={key}")
    DbSet.iterator(/webmail/folders[owner == key]) |> Iter.to_list
  }

  /** Return in client format the list of user folders. */
  function list_boxes(User.key key) {
    debug("Get all client folders for user {key}")
    DbSet.iterator(/webmail/folders[owner == key].{id, name}) |> Iter.to_list
  }

  /** Retrieve a specific folder. */
  function get(User.key owner, Folder.id id) {
    debug("get folder {id}")
    ?/webmail/folders[~{id, owner}]
  }

  /** Return the content of a box. */
  function get_content(User.key owner, Folder.id id) {
    ?/webmail/folders[~{id, owner}]/content ? {count: 0, starred: 0, unread: 0, new: 0}
  }

  /** Return the folder name. */
  exposed function name(Folder.id id) {
    DbUtils.option(/webmail/folders[id == id]/name)
  }

  /**
   * Update the content of a specific box.
   * The arguments are differentials to apply to the db counts.
   */
  function update_content(User.key owner, Folder.id id, dcount, dunread, dstarred, dnew) {
    /webmail/folders[~{id, owner}] <- {content.count += dcount, content.unread += dunread, content.starred += dstarred, content.new += dnew}
  }
  function set_content(User.key owner, Folder.id id, content) {
    /webmail/folders[~{id, owner}] <- ~{content}
  }

  /**
   * Insert new messages, and apply the folder changes it implies.
   * Do not apply with team keys.
   */
  function insert_message(User.key owner, Message.status status) {
    id = Box.identifier(status.mbox)
    dcount = 1
    dunread = if (not(status.flags.read)) 1 else 0
    dstarred = if (status.flags.starred) 1 else 0
    dnew = if (not(status.opened)) 1 else 0
    if (Team.key_exists(owner))
      User.get_team_users([owner]) |>
      Iter.iter(function (user) { update_content(user.key, id, dcount, dunread, dstarred, dnew) }, _)
    else
      update_content(owner, id, dcount, dunread, dstarred, dnew)
  }

  /**
   * Insert messages for a list of owners.
   * Teams are treated separatly, so as to avoid duplicate insertions.
   */
  function insert_messages(list(User.key) owners, (User.key -> Message.status) status) {
    (teams, users) = List.partition(Team.key_exists, owners)
    // Insert regular owners.
    List.iter(function (user) { insert_message(user, status(user)) }, users)
    // Insert team members.
    match (teams) {
      case [team|_]:
        status = status(team)
        User.get_team_users(teams) |> Iter.iter(function (user) {
          // Excluded users for whom the message has already been added.
          if (not(List.mem(user.key, users)))
            insert_message(user.key, status)
        }, _)
      default: void
    }
  }

  /**
   * Delete a message and update the folder content.
   * As messages cannot be deleted by teams, there is no need to propagate
   * the modifications to team memebrs, as is the case with {insert_message}.
   */
  function delete_message(User.key owner, Message.status status) {
    id = Box.identifier(status.mbox)
    dcount = -1
    dunread = if (not(status.flags.read)) -1 else 0
    dstarred = if (status.flags.starred) -1 else 0
    dnew = if (not(status.opened)) -1 else 0
    update_content(owner, id, dcount, dunread, dstarred, dnew)
  }

  /**
   * Content update function, which must be called after all team changes.
   * The function is commonn to team deletion and addition, the only difference
   * being the message function calls.
   *
   * @param diff the difference between new and old sets of teams.
   * @param teams the new or old set of teams, depending on the operation.
   * @param lock if true, messages are purged from the folders, else imported.
   */
  @async function void swap(User.key owner, list(Team.key) diff, list(Team.key) teams, bool lock) {
    debug("diff: owner={owner} diff={diff} teams={teams}")
    if (diff == []) void
    else
      // Restore each folder.
      DbSet.iterator(/webmail/folders[owner == owner]/id) |>
      Iter.iter(function (id) {
        debug("diff: managing {id}")
        if (List.mem(id, ["STARRED", "DELETED"])) void // Non-physical boxes.
        else {
          contents = Message.swap(owner, Box.iparse(id), diff, teams, lock)
          debug("diff: swapped {contents}")
          // Update box.
          if (lock) /webmail/folders[~{owner, id}] <- {content: {count -= contents.count, new -= contents.new, unread -= contents.unread, starred -= contents.starred}}
          else      /webmail/folders[~{owner, id}] <- {content: {count += contents.count, new += contents.new, unread += contents.unread, starred += contents.starred}}
        }
      }, _)
  }

  @expand function void import(owner, diff, teams) { swap(owner, diff, teams, false) }
  @expand function void purge(owner, diff, teams) { swap(owner, diff, teams, true) }

  /** Specifically fetch the message count of a box. */
  function count(User.key owner, Mail.box box) {
    match (box) {
      case {starred}:
        DbSet.iterator(/webmail/folders[owner == owner]/content/starred) |> Iter.fold(`+`, _, 0)
      default:
        id = Box.identifier(box)
        ?/webmail/folders[~{id, owner}]/content/count ? 0
    }
  }

  /** Check whether the given id corresponds to a folder or not. */
  function bool id_exists(User.key owner, string id) {
    ?/webmail/folders[~{id, owner}].{} |> Option.is_some
  }

  /** See if the folder name is attributed. */
  function bool exists(User.key key, string name) {
    DbUtils.option(/webmail/folders[owner == key and name == name].{}) |> Option.is_some
  }

  /** Folder clear name. */
  function get_name(User.key owner, Folder.id id) {
    ?/webmail/folders[~{id, owner}]/name
  }

  /** Find the id associated with a name. */
  function find(User.key key, string name) {
    DbUtils.option(/webmail/folders[owner == key and name == name].{id}) |> Option.map(_.id, _)
  }
}

