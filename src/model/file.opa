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

abstract type File.id = DbUtils.oid

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

/** User access rights. */
type File.access =
  {admin} or     // Write + share access.
  {read} or      // Read only.
  {write}        // Read and Write.

/** Generic file location. */
type File.location =
  {Directory.id directory} or
  {Path.t path}

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

type File.t = {
  File.id id,                // Unique id.
  User.key owner,            // File owner (=creator).
  Label.id security,         // File security.

  RawFile.id published,      // Published version.
  int version,               // Version counter.
  Date.date created,         // Upload date.
  option(Date.date) deleted  // File deleted.
}

database File.t /webmail/files[{id}]
database /webmail/files[_]/deleted = none


module File {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[File]", msg) }
  private function warning(msg) { Log.warning("[File]", msg) }

  @stringifier(File.id) function sofid(id) { DbUtils.OID.sofid(id) }
  function File.id idofs(string s) { s }
  File.id dummy = DbUtils.OID.dummy


  /** {1} File creation. */

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

  /** General getters. */
  function get(File.id id) { ?/webmail/files[id == id] }
  function getPublished(File.id id) { ?/webmail/files[id == id]/published }
  function getClass(File.id id) { DbUtils.option(/webmail/files[id == id and deleted == none]/security) }
  function getOwner(File.id id) { ?/webmail/files[id == id]/owner }

  /** Getters applying to the current raw version. */
  function getName(File.id id) { Option.bind(RawFile.getName, getPublished(id)) }
  function getRaw(File.id id) { Option.bind(RawFile.get, getPublished(id)) }
  function getMetadata(File.id id) { Option.bind(RawFile.getMetadata, getPublished(id)) }

  /** Refer to RawFile namesakes. */
  function getResource(File.id id) { Option.bind(RawFile.getResource, getPublished(id)) }
  function getAttachment(File.id id, bool data) { Option.bind(RawFile.getAttachment(_, data), getPublished(id)) }
  function getPayload(File.id id, string partId) { Option.bind(RawFile.getPayload(_, partId), getPublished(id)) }


  /** {1} Querying. */

  /** Used once for solr reindexing. FIXME: COMPLEXITY is not acceptable. */
  function iterator() { DbSet.iterator(/webmail/files) }
  /** FIXME complexity is not acceptable. */
  function count(option(User.key) key) {
    match (key) {
      case {none}: DbSet.iterator(/webmail/files.{}) |> Iter.count
      case {some: key}: DbSet.iterator(/webmail/files[owner == key and deleted == {none}].{}) |> Iter.count
    }
  }


  /** {1} Modifiers. */

  /** Return the version number of the given file, and increment it in the database. */
  function version(File.id id) {
    last = ?/webmail/files[id == id]/version
    match (last) {
      case {some: version}:
        /webmail/files[id == id] <- {version++}
        version
      default: 0
    }
  }

  /**
   * Rename the published version of the file, and propagates the changes to
   * associated tokens.
   */
  function rename(File.id id, string newname) {
    log("rename: id={id} newname={newname}")
    match (getMetadata(id)) {
      case {some: metadata}:
        if (metadata.name != newname) {
          RawFile.rename(metadata.id, newname)
          // Publish changes.
          metadata = {metadata with name: newname}
          DbSet.iterator(/webmail/filetokens[file == id]) |>
          Iter.iter(function (token) { FileToken.update(token, metadata) |> ignore }, _)
        }
      default: void
    }
  }

  /**
   * Same as {publish}, but the changes are immediatly propagated to the tokens attached to the file.
   * @return the version number that must be given to the raw file.
   */
  function revise(File.id id, RawFile.t raw) {
    last = ?/webmail/files[id == id]/version
    match (last) {
      case {some: version}:
        /webmail/files[id == id] <- {version++, published: raw.id}
        DbSet.iterator(/webmail/filetokens[file == id]) |>
        Iter.iter(function (token) { FileToken.update(token, raw) |> ignore }, _)
        version
      default: 0
    }
  }

  /** Same as {revise}, where the raw file hasn't been created yet. */
  function modify(File.id id, binary data, string mimetype, string filename, User.key owner) {
    last = ?/webmail/files[id == id]/version
    match (last) {
      case {some: version}:
        // Create the raw file with these parameters.
        raw = RawFile.create(owner, filename, mimetype, data, id, version, none)
        /webmail/files[id == id] <- {version++, published: raw.id}
        DbSet.iterator(/webmail/filetokens[file == id]) |>
        Iter.iter(function (token) { FileToken.update(token, raw) |> ignore }, _)
        version
      default: 0
    }
  }

  /** Return the history of the modifications of a file. */
  function history(File.id file) {
    DbSet.iterator(/webmail/rawfiles[
      file == file and deleted == false; order -version
    ].{id, size, mimetype, created, thumbnail, name, encryption, file, owner}) |> Iter.to_list
  }

  /**
   * Delete a file version from the file's history. If the selected version is the published one,
   * the next version in the history is selected and published. If only one version remains, or if the
   * provided rawfile is not a version of the file, the operation fails.
   *
   * @return the new published version (if successful).
   */
  function option(RawFile.id) deleteVersion(File.id file, RawFile.id version) {
    log("deleteVersion: file={file} version={version}")
    // Gather the list of file versions.
    history = DbSet.iterator(/webmail/rawfiles[
      file == file and deleted == false; order -version
    ]/id) |> Iter.to_list
    published = ?/webmail/files[id == file]/published ? version
    size = List.length(history)
    // Cannot delete the version without deleting the file.
    if (size <= 1) {
      log("deleteVersion: cannot delete last version of {file}")
      none
    } else
      match (List.index(version, history)) {
        // The version is not part of the file history.
        case {none}:
          log("deleteVersion: {version} is not a version of {file}")
          none
        case {some: n}:
          // Select a new version to be published if necessary.
          if (version == published) {
            index = if (n == size-1) n-1 else n+1
            newVersion = List.nth(index, history) ? version
            if (publishVersion(file, newVersion)) {
              RawFile.delete(version)
              some(newVersion)
            } else none
          } else {
            RawFile.delete(version)
            some(published)
          }
      }
  }

  /**
   * Modify the published version of the file. The function assumes pub is already a version of the file.
   * Updates all the tokens attached to this file.
   */
  function bool publishVersion(File.id id, RawFile.id version) {
    match (RawFile.getMetadata(version)) {
      case {some: metadata}:
        /webmail/files[id == id] <- {published: version}
        DbSet.iterator(/webmail/filetokens[file == id]) |>
        Iter.iter(function (token) { FileToken.update(token, metadata) |> ignore }, _)
        true
      case {none}: false
    }
  }

  /** Change the classification of the file (propagates the change to all associated tokens). */
  function setClass(File.id id, Label.id security) {
    @catch(Utils.const(false), {
      /webmail/files[id == id] <- ~{security; ifexists}
      /webmail/filetokens[file == id] <- ~{security}
      true
    })
  }

  /**
   * Set the security label of a file. The difference with the preceding function
   * lies in the fact that the security is changed iff the previous label is
   * 'default', 'notify' or 'attached'.
   */
  function addClass(File.id id, Label.id security) {
    match (getClass(id)) {
      case {some: previous}:
        if (previous == Label.attached.id ||
            previous == Label.open.id ||
            previous == Label.internal.id ||
            previous == Label.notify.id)
            setClass(id, security) |> ignore
      case {none}: void
    }
  }

  /** {1} Access checks. */

  function canWrite(User.key user, File.id id) {
    teams = User.get_teams(user)
    match (DbUtils.option(/webmail/filetokens[file == id and owner in [user|teams]]/access)) {
      case {some: access}: Access.write(access)
      default: false
    }
  }
  function canRead(User.key user, File.id id) {
    teams = User.get_teams(user)
    DbUtils.exists(/webmail/filetokens[file == id and owner in [user|teams]; limit 1].{})
  }

  /** {1} Operations on user access rights. */

  module Access {

    /** Check whether the user has write access. */
    function write(File.access a) {
      match (a) {
        case {read}: false
        case {admin} case {write}: true
      }
    }

    /** Check whether the user can share the file. */
    function share(File.access a) {
      a == {admin}
    }

    /** Check whether a0 >> a1. */
    function imply(File.access a0, File.access a1) {
      pair = (a0, a1)
      match (pair) {
        case ({admin}, _): true
        case (_, {admin}): false
        case ({write}, _): true
        case (_, {write}): false
        case ({read}, {read}): true
      }
    }

    /** Return the highest access rights of the two. */
    function max(File.access a0, File.access a1) {
      pair = (a0, a1)
      match (pair) {
        case ({admin}, _)
        case (_, {admin}): {admin}
        case ({write}, _)
        case (_, {write}): {write}
        default: {read}
      }
    }
  } // END ACCESS

} // END FILE.
