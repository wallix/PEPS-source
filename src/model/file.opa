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

/**
 * File encryption. If the encryption is not none,
 * the fields nonce and key will be set to the parameters
 * used for the encryption of the message. The key will be
 * either: the public key generated for the file
 * (in RawFile.t), or the encrypted secret key
 * (in FileToken.t).
 */
type File.encryption =
  { string nonce,
    string key } or
  { none }

/**
 * The files contain the information common to a series of verions.
 * In particular:
 *   - the version counter
 *   - the published version
 *   - the security label
 * Files are shared amongst all users, and as such are not part of the file system.
 * Consequently, they cannot be accessed directly: a token must be created to incorporate
 * it in the user's file system.
 * The file type does not include labels, as those are specific to each user.
 */

abstract type File.id = DbUtils.oid

type File.t = {
  File.id id,                // Unique id.
  User.key owner,            // File owner.
  Label.id security,         // File security.

  RawFile.id published,      // Published version.
  int version,               // Version counter.
  Date.date created,         // Upload date.
  option(Date.date) deleted  // File deleted.
}

database File.t /webmail/files[{id}]
database /webmail/files[_]/deleted = {none}

/**
 * Link a File with a Mail message. Used
 * as a reversed index to query which mails a file is attached to.
 */

type MailFile.t = {
  User.key key,              // Not necessarily the owner of the file.
  File.id id,                // Mail attachment.
  list(Message.id) mids      // List of mails containing the attachment.
}

database MailFile.t /webmail/mailfiles[{key, id}]


module File {

  private function log(msg) { Log.notice("File:", msg) }
  @stringifier(File.id) function sofid(id) { DbUtils.OID.sofid(id) }
  function File.id idofs(string s) { s }
  File.id dummy = DbUtils.OID.dummy

  /**
   * {1 File creation.}
   */

  /** Insert a file in the database. */
  private function insert(File.t file) {
    /webmail/files[id == file.id] <- file
    file
  }

  /**
   * Create a new file, and the initial raw version at the same time.
   * @return both the file and rawfile created.
   */
  protected function create(User.key owner, name, mimetype, binary content, Label.id security) {
    id = DbUtils.OID.gen()
    raw = RawFile.create(owner, name, mimetype, content, id, 0, none)
    file = ~{
      id, owner, security,
      published: raw.id, version: 1,
      created: Date.now(), deleted: none
    }
    ~{file: insert(file), raw}
  }

  /** Transform a raw file into a file. */
  protected function import(RawFile.t raw, Label.id security) {
    id = DbUtils.OID.gen()
    file = ~{
      id, owner: raw.owner, security,
      published: raw.id, version: 2, // Version 1 reserved for the imported raw.
      created: Date.now(), deleted: {none}
    }
    insert(file)
  }

  /** {1} Getters. */

  function get(File.id id) {
    ?/webmail/files[id == id]
  }
  function get_published(File.id id) {
    ?/webmail/files[id == id]/published
  }
  function get_security(File.id id) {
    DbUtils.option(/webmail/files[id == id and deleted == {none}]/security)
  }
  function get_owner(File.id id) {
    ?/webmail/files[id == id]/owner
  }

  /** Return the name of the published version. */
  function get_name(File.id id) { Option.bind(RawFile.get_name, get_published(id)) }

  /** Return the published version (the entire file, not just the id). */
  function get_raw(File.id id) { Option.bind(RawFile.get, get_published(id)) }
  function get_raw_metadata(File.id id) { Option.bind(RawFile.get_metadata, get_published(id)) }

  /** Refer to RawFile.getResource. */
  function getResource(File.id id) { Option.bind(RawFile.getResource, ?/webmail/files[id == id]/published) }
  /** Refer to RawFile.getAttachment. */
  function getAttachment(File.id id, bool data) { Option.bind(RawFile.getAttachment(_, data), ?/webmail/files[id == id]/published) }
  /** Refer to RawFile.getPayload. */
  function getPayload(File.id id, string partId) { Option.bind(RawFile.getPayload(_, partId), ?/webmail/files[id == id]/published) }

  /** {1} Querying. */

  // FIXME: COMPLEXITY is not acceptable
  // used once for solr_search reextract
  function iterator() {
    DbSet.iterator(/webmail/files)
  }
  // FIXME: COMPLEXITY is not acceptable
  // used once for solr_search reextract
  function count(option(User.key) key) {
    ( match (key) {
      case {none}: DbSet.iterator(/webmail/files.{})
      case {some: key}: DbSet.iterator(/webmail/files[owner == key and deleted == {none}].{})
    })
    |> Iter.count
  }

  function iterator_of(list(File.id) ids) {
    DbSet.iterator(/webmail/files[id in ids])
  }

  /**
   * {1 Modifiers.}
   */

  /**
   * Return the version number of the given file, and increment it in the database.
   */
  function version(File.id id) {
    last = ?/webmail/files[id == id]/version
    match (last) {
      case {some: version}:
        /webmail/files[id == id]/version++
        version
      default:
        0
    }
  }

  function update_security(File.id id, Label.id security) {
    @catch(Utils.const(false), {
      /webmail/files[id == id]/security <- security
      /webmail/filetokens[file == id] <- ~{security}
      true
    })
  }

  /**
   * Set the security label of a file. The difference with the preceding function
   * lies in the fact that the security is changed iff the previous label is
   * 'default', 'notify' or 'attached'.
   */
  function add_security(File.id id, Label.id security) {
    match (get_security(id)) {
      case {some: previous}:
        if (previous == Label.attached.id ||
            previous == Label.open.id ||
            previous == Label.internal.id ||
            previous == Label.notify.id)
            update_security(id, security) |> ignore
      case {none}: void
    }
  }

  /**
   * Modify the published version of the file.
   */
  function publish(File.id id, RawFile.id pub) {
    @catch(Utils.const(false), {
      /webmail/files[id == id]/published <- pub
      true
    })
  }

}

module MailFile {

  private function log(msg) { Log.notice("MailFile:", msg) }

  /**
   * The index is created only if not present in the db.
   */
  function void create(User.key key, id) {
    if (DbUtils.option(/webmail/mailfiles[key == key and id == id]) |> Option.is_some) void
    else
      /webmail/mailfiles[key == key and id == id] <- ~{key, id, mids: []}
  }

  /**
   * Define the file [id] as attachment of the mail [mid].
   */
  function void attach(key, id, mid) {
    // Ensure that the structure exists.
    create(key, id)
    // Add the file.
    /webmail/mailfiles[key == key and id == id]/mids <+ mid
  }

 /**
   * Remove the file [id] as attachment of the mail [mid].
   */
  function void detach(User.key key, File.id id, Message.id mid) {
    /webmail/mailfiles[key == key and id == id]/mids <--* mid
  }

  /**
   * Return the lit of mails the given file is attached to.
   */
  function get(User.key key, File.id id) {
    /webmail/mailfiles[key == key and id == id]/mids
  }

}
