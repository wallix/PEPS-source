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

/** {1} Type declarations. */

/**
 * FIXME: DbUtils.oid is not a counter: see apis/mongo/wire_protocol.opa in
 * the standard library. Replace a distributed counter (in reddis for ex).
 */
type Journal.id = DbUtils.oid

// type Journal.direction =
//    {in}  // Means the event come from an external service.
// or {out} // Means the event come from our internal service.

/** Common journal entries, only lacking a flavor (draft, mail, folder ...). */
type Journal.Common.event =
  {new} or
  {delete} or
  {update}

/** Journal entries for labels. */
type Journal.Common.label = {
  list(string) added,
  list(string) removed
}

/** Mail related journal entries. */
type Journal.Message.event =
  {(Journal.Common.event or {send}) mail} or     // Mail events.
  {(Journal.Common.event or {send}) draft} or    // Draft events.
  {Journal.Common.event folder} or               // Folder events.
  {Email.send_status send} or                    // Send status (only added if external addresses).
  // Flags.
  {Journal.Common.label label} or    // Adding and removing labels from a mail (including security classes).
  {{string src, string dst} move} or // Obvious.
  {User.key opened} or               // User opened a message.
  {bool read} or                     // Flag: read.
  {bool star} or                     // Flag: starred.
  {failed}

type Journal.Message.t = {
  Journal.id id,               // Unique id.
  User.key key,                // User (or team) concerned by the event.
  Message.id mid,              // Message object of the event.
  Date.date date,              // Date of the event.
  Journal.Message.event event, // Type.
  list(string) mboxes          // List of the mail boxes concerned by this event.
}

/** Events viewable on the dashboard. */
type Journal.Main.event =
  {Journal.Common.event evt, Team.key team} or            // Sub-team creation / deletion / edition.
  {Message.id message, string snippet, string subject, Mail.address from} or // Team message.
  {Journal.Common.event evt, User.key user} or            // new = User enters team ; delete = user leaves team.
  {Journal.Common.event evt, string name, int size, string mimetype, RawFile.id file, bool thumbnail, FileToken.id token} or        // File events.
  {Journal.Common.event evt, Directory.id dir}            // Directory events.
  /** More to come ? */

type Journal.Main.t = {
  Journal.id id,               // Unique id.
  User.key creator,            // Initiator of the entry.
  list(User.key) owners,       // Teams and users concerned by the event.
  Date.date date,              // Date of the event, on the local server.
  Journal.Main.event event     // Type of the event.
}

/**
 * File and directory related journal entries.
 * Only file tokens are included.
 */
/*
type Journal.FS.event =
  Journal.Common.event or
  {failed}
or {delete}
or {string security}   // Change the security (if the security is empty, then remove).
or {string rename}
or {{string src, string dst} move}
or {update}            // Local revisions and external updates.
or {string share}      // Private sharing. string == User.key
or {string unshare}
or {string link}       // Public link. string == Share.link
or {string unlink}

type Journal.FS.t = {
  Journal.id id,          // Unique id.
  User.key key,           // User concerned by the event.
  Date.date date,         // Date of the event, on the local server.
  Share.source src,       // Source of the event (a file or a directory).
  Journal.FS.event event, // Type of the event.
  // Journal.direction direction
} */

/** Admin actions: label, team, user creation and update. */
type Journal.Admin.event =
  {Journal.Common.event user} or // User creation, deletion and updates. Teams updates are separate and given by the membership events.
  {Journal.Common.event team} or // Sub-team creation / deletion / edition.
  {failed}

type Journal.Admin.src =
  {user} or
  {team}

/**
 * Structured type for admin events.
 * Events are identified for a list of teams, so as to be readily
 * queried for user dashboards.
 */
type Journal.Admin.t = {
  Journal.id id,             // Unique id.
  User.key creator,          // User who triggered the event.
  Date.date date,            // Date of the event, GMT time.
  string src,                // Source of the event (a user, team or label).
  Journal.Admin.event event  // Type of the event.
}

/** Specific entries (applications). */
/*type Journal.App.event = string

type Journal.App.t = {
  Journal.id id,           // Unique id.
  string app,              // Name of the application concerned.
  User.key key,            // User concerned by the event.
  Date.date date,          // Date of the event, on the local server.
  Journal.App.event event, // Type of the event.
  Journal.direction direction
}*/

/** {1} Database declarations. */

database Journal.Message.t /webmail/journals/message[{id}]
database Journal.Admin.t /webmail/journals/admin[{id}]
database Journal.Main.t /webmail/journals/main[{id}]
// database Journal.FS.t /webmail/journals/fs[{id}]
// database Journal.App.t /webmail/journals/app[{id}]

database /webmail/journals/message[_] full
database /webmail/journals/admin[_] full
database /webmail/journals/main[_] full
// database /webmail/journals/fs[_] full
// database /webmail/journals/app[_] full

module Journal {

  /**
   * [DbUtils.OID.genuid] increments a counter, so consecutive calls to [genid] would return
   * ordered ids. However, this may not be true if multiple servers were to be used.
   * TODO: implement a distributed counter, through redis.
   */
  protected function Journal.id genid() { DbUtils.OID.genuid() }
  @stringifier(Journal.id) function string sofid(Journal.id id) { DbUtils.OID.sofid(id) }

  /** {1} Mail journal. */

  module Message {

    /** Saves a journal entry. */
    function Journal.id log(User.key key, Message.id mid, Journal.Message.event event) {
      entry = ~{
        id: genid(), date: Date.now(),
        key, event, mid, mboxes: affected_mboxes(event)
      }
      /webmail/journals/message[id==entry.id] <- entry
      entry.id
    }

    /**
     * Add the journal entries associated with the sending of a mail:
     *  - the sender gets a 'sent' entry.
     *  - each receiver gets a 'new' entry.
     * NB: the given message can be partial.
     * If the message was previously a draft, a separate entry will be added
     * to record the change {draft} -> {sent}.
     */
    protected function log_send(Message.full message, draft) {
      // Sender.
      header = message.header
      sentlog =
        if (draft) log(header.creator, header.id, {draft: {send}})
        else       log(header.creator, header.id, {mail: {send}})
      // Internal receivers.
      List.iter(function (key) {
        if (key != header.creator) log(key, header.id, {mail: {new}}) |> ignore
      }, message.owners)
      sentlog
    }

    /**
     * Fetch a fixed amount of history records, unconditionally.
     * Only events concerning mail movements are kept: label, move, read, star.
     */
    function history(User.key key, Journal.id lastId, int maxResults, option(string) mbox) {
      match (mbox) {
        case {some: mbox}:
          DbSet.iterator(/webmail/journals/message[
            key == key and id > lastId and mboxes[_] == mbox and
            (event.move exists or event.label exists or event.read exists or event.star exists or event.mail exists);
            order +date; limit maxResults ])  |> Iter.to_list
        default:
          DbSet.iterator(/webmail/journals/message[
            key == key and id > lastId and
            (event.move exists or event.label exists or event.read exists or event.star exists or event.mail exists);
            order +date; limit maxResults ]) |> Iter.to_list
      }
    }

    /**
     * Return the id of the last entry in the history of a user.
     * Normally, entries should always exist.
     */
    function last(User.key key) {
      entry = DbUtils.option(/webmail/journals/message[key==key; order -date; limit 1].{id})
      Option.map(_.id, entry) ? ""
    }

    /** Return the id of the journal entry that last modified a message. */
    function last_modification(User.key key, Message.id mid) {
      DbUtils.option(/webmail/journals/message[key==key and mid==mid; order -date; limit 1].{id})
    }

    /** Delete the journal entries of the given user. */
    function delete(User.key key) {
      DbSet.iterator(/webmail/journals/message[key == key].{id}) |>
      Iter.iter(function(entry) {
        Db.remove(@/webmail/journals/message[id == entry.id])
      }, _)
    }

    /** Convert a event to a string. */
    @stringifier(Journal.Message.event) event_to_string = function {
      case {mail: evt}: "{evt} mail"
      case {draft: evt}: "{evt} draft"
      case {folder: evt}: "{evt} folder"
      case {send: status}: "mail send status: {status}"
      case ~{read}: "read: {read}"
      case ~{opened}: "opened by {opened}"
      case ~{star}: "starred: {star}"
      case ~{move}: "move: {move.src} -> {move.dst}"
      case ~{label}: "label: added {label.added}; removed {label.removed}"
      case {failed}: "failed"
    }

    /** Return the list of mail boxes affected by the given journal event. */
    private function affected_mboxes(Journal.Message.event evt) {
      match (evt) {
        case {mail: {new}}: ["INBOX"]
        case {mail: {send}}: ["SENT"]
        case {mail: {delete}}: ["TRASH"] // Only mails already in the trash can be deleted.
        case {read: _}: ["UNREAD"]
        case {star: _}: ["STARRED"]
        case ~{move}: [move.src, move.dst]
        case ~{label}: label.added ++ label.removed
        default: []
      }
    }

  } // END MESSAGE

  /** {1} Admin journal. */

  module Admin {

    /** Saves a journal entry. */
    function Journal.id log(User.key creator, string src, Journal.Admin.event event) {
      entry = ~{ id: genid(), date: Date.now(), creator, event, src }
      /webmail/journals/admin[id == entry.id] <- entry
      entry.id
    }

    /**
     * Fetch the recent history.
     * @param src identifies the kind of entries to return.
     */
    function history(User.key creator, Journal.id lastId, int maxResults, Journal.Admin.src src) {
      match (src) {
        case {user}:
          DbSet.iterator(/webmail/journals/admin[
            creator==creator and id>lastId and (event.user exists); order +date; limit maxResults
          ]) |> Iter.to_list
        case {team}:
          DbSet.iterator(/webmail/journals/admin[
            creator==creator and id>lastId and (event.team exists); order +date; limit maxResults
          ]) |> Iter.to_list
      }
    }

    /**
     * Return the id of the last entry in the history of a user.
     * Normally, entries should always exist.
     */
    function last(User.key creator) {
      entry = DbUtils.option(/webmail/journals/admin[creator==creator; order -date; limit 1].{id})
      Option.map(_.id, entry) ? ""
    }

    /** Return the id of the journal entry that last modified an obbject. */
    function last_modification(User.key creator, string src) {
      DbUtils.option(/webmail/journals/admin[creator==creator and src==src; order -date; limit 1].{id})
    }

    /** Delete the journal entries of the given user. */
    function delete(User.key creator) {
      DbSet.iterator(/webmail/journals/admin[creator == creator].{id}) |>
      Iter.iter(function(entry) {
        Db.remove(@/webmail/journals/admin[id == entry.id])
      }, _)
    }

    /** Convert a event to a string. */
    @stringifier(Journal.Admin.event) event_to_string = function {
      case {user: evt}: "{evt} user"
      case {team: evt}: "{evt} team"
      case {failed}: "failed"
    }

  } // END ADMIN

  /** {1} Main events. */

  module Main {

    /** Save a journal entry. */
    function Journal.id log(User.key creator, list(Team.key) owners, Journal.Main.event event) {
      entry = ~{ id: genid(), creator, date: Date.now(), owners, event }
      /webmail/journals/main[id == entry.id] <- entry
      entry.id
    }

    /** Fetch the recent history. */
    function history(list(User.key) owners, Date.date ref, int maxResults) {
      DbSet.iterator(/webmail/journals/main[owners[_] in owners and date < ref; order -date; limit maxResults])
    }

    /** Fetch events, and format them into a page. */
    function page(owners, Date.date ref, int maxResults) {
      history(owners, ref, maxResults) |> Iter.to_list |> Utils.page(_, _.date, ref)
    }

  } // END MAIN.

}
