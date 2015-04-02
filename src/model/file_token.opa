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
 * File tokens give access to shared files. The most basic token
 * is the one owned by the owner of the file: it gives admin rights.
 * Access rights can be:
 *   - admin: can read, modify, and share the file.
 *   - write: can modify the file.
 *   - read: read only.
 */

abstract type FileToken.id = DbUtils.oid

/** Origin of the file. */
type File.origin =
  {Message.id email} or      // Received as messages.
  {upload} or                // File uploaded through API or resumable.
  {User.key shared} or       // Shared by a user.
  {internal}                 // Internally generated files.

/**
 * Decomposition of a file name.
 * The final filename will be "{base} [({version})][.{ext}]".
 * The version number is only used by the token to distinguish between
 * identically named files: the raw file keeps its original name.
 */
type File.name = {
  string base,      // Base name.
  int version,      // Unique for files with identical names in the same directory.
  string ext,       // File extension.
  string fullname   // Full filename.
}

/**
 * Type of file tokens.
 * Includes:
 *  - general metadata, including version selector.
 *  - directory.
 *  - metadata copied from the raw file.
 */
type FileToken.t = {
  FileToken.id id,           // Unique id.
  User.key owner,            // Owner of the token.
  File.name name,            // File name: the same as the active version.
  // Versioning.
  File.origin origin,        // Source of the token.
  File.id file,              // The file the token gives access to.
  RawFile.id active,         // The file active version.
  File.access access,        // User access rights.
  bool hidden,               // Hide the file token in the directory view.
  option(Share.link) link,   // An optional share link.
  option(Directory.id) dir,  // Parent directory (local to the owner's file system).
  Label.labels labels,       // Personal labels.
  Label.id security,         // Security class.
  File.encryption encryption, // Encryption parameters.
  Date.date created,         // Upload date.
  Date.date edited,          // Edition date == last version change.
  option(Date.date) deleted, // File deleted.
  // Imported from the active version (which should be the file's published version).
  int size, string mimetype,
  option(RawFile.thumbnail) thumbnail
}

/** File snippet, with highlighted content. */
type FileToken.snippet = {
  FileToken.id id,
  RawFile.id active,
  option(string) highlighted // highlighted content (of the active version).
}

/** Type of implemented db queries. */
type FileToken.query = {
  bool teams,                                            // Lookup team files as well.
  {option(Directory.id) dir} or {everywhere} location,   // Limit the query to the files in a directory.
   // Term of the query.
  {string name} or
  {File.id file} or
  {RawFile.id active} query
}

/** Search filter. */
type FileToken.filter = {
  string name      // Empty == unconstrained.
}

database FileToken.t /webmail/filetokens[{id}]
database /webmail/filetokens[_]/deleted = none
database /webmail/filetokens[_]/thumbnail full
database /webmail/filetokens[_]/origin = {internal}
database /webmail/filetokens[_]/access = {read}
database /webmail/filetokens[_]/hidden = false


module FileToken {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[FileToken]", msg) }
  private function warning(msg) { Log.warning("[FileToken]", msg) }

  @stringifier(FileToken.id) function sofid(id) { DbUtils.OID.sofid(id) }
  private dummy = DbUtils.OID.dummy

  both emptyFilter = {name: ""}
  both function FileToken.filter parseFilter(string value) { {name: value} }

  /** Add appropriate journal logs for a token action. */
  function journallog(FileToken.t token, evt) {
    thumbnail = if (token.thumbnail == none) none else some(token.active)
    owner = token.owner
    // if (Team.key_exists(owner))
    Journal.Main.log(
      "", [owner],
      ~{ evt, token: token.id, file: token.active, name: token.name.fullname,
         size: token.size, mimetype: token.mimetype, thumbnail: token.thumbnail != none }
    ) |> ignore
    // else void
      // TODO add file logs.
      // Journal.File.log(owner, ..)
  }

  /**
   * Extract the metadata of the token's active version _ which is stored for
   * efficiency in the token (except for the raw file encryption).
   * NB: the owner is NOT correct in the returned metadata.
   */
  both function RawFile.metadata metadata(FileToken.t token) {
    { id: token.active, created: token.edited, name: token.name.fullname,
      thumbnail: token.thumbnail, size: token.size, mimetype: token.mimetype,
      encryption: token.encryption, owner: token.owner, file: token.file }
  }

  /** Create a file snippet by adding content highlightings. */
  both function FileToken.snippet highlight(token, option(string) content) { { id: token.id, active: token.active, highlighted: content } }

  /** Compute the 'full' field of a filename. */
  function with_fullname(filename) {
    version = if (filename.version > 0) " ({filename.version})" else ""
    ext = if (filename.ext != "") ".{filename.ext}" else ""
    {filename with fullname: "{filename.base}{version}{ext}"}
  }

  /** Create a filename. */
  function parse_filename(string name) {
    function filename(block) {
      version = parser { case "(" i=Rule.natural ")": i }
      filename = parser {
        case s=(( !(version !.) . )*) i=version:
          {base: String.strip_right(Text.to_string(s)), version: i, ext: "", fullname: name}
      }
      match (Parser.try_parse(filename, block)) {
        case {some: filename}: filename
        default: {base: block, version: 0, ext: "", fullname: name}
      }
    }
    void  // Necessary, else syntax error.
    match (List.rev(String.explode(".", name))) {
      case [b]: filename(b)
      case [ext,b]:
        {filename(b) with ~ext}
      case [ext,b|bs]:
        fname = filename(b)
        base = List.rev(bs) |> List.to_string_using("", ".", ".", _)
        ~{fname with base: base + fname.base, ext}
      default: {base: name, version: 0, ext: "", fullname: name}
    }
  }

  /**
   * Create a unique filename for the given file and directory:
   * the function looks up files with identical names and picks up an unused version number.
   * @param id the id of the token (or none if token creation). Necessary to avoid clash with own name.
   */
  function filename(option(FileToken.id) id, User.key owner, string name, option(Directory.id) dir) {
    filename = parse_filename(name)
    tid = id ? ""
    existing =
      (DbSet.iterator(/webmail/filetokens[
        owner == owner and dir == dir and id != tid and
        name.base == filename.base and name.ext == filename.ext
      ].{id, name}))

    (if (Iter.exists(function (token) { token.name.version == filename.version }, existing))
      match (Iter.max_by(_.name.version, existing)) {
        case {some: max}: {filename with version: max.name.version+1}
        default: filename
      }
    else filename) |> with_fullname
  }

  /** {1} File creation. */

  /**
   * Construct a token.
   * The id is automatically generated.
   * The active version is set to the published version of the file.
   * [hidden] is set to false.
   */
  function make(User.key owner, origin, file, raw, access, dir, hidden, encryption) {
    id = DbUtils.OID.gen()
    security = File.getClass(file) ? Label.open.id
    filename = filename(none, owner, raw.name, dir)
   ~{ id, owner, origin, name: filename,
      file, active: raw.id, access, link: none,
      size: raw.size, thumbnail: raw.thumbnail, mimetype: raw.mimetype,
      dir, labels: [], created: Date.now(), edited: Date.now(),
      deleted: none, hidden, security, encryption }
  }

  /** Insert a file in the database. */
  private function insert(FileToken.t file) {
    /webmail/filetokens[id == file.id] <- file
    journallog(file, {new}) // Journal.
    file
  }

  /**
   * Create a new token to a given file, with the specified version.
   *
   * @param file determines the file the token points to.
   * @param raw must be at least of type {Raw.metadata}. Must be a version of {file}.
   * @param hidden if set to true, the file will never appear in the view (except implicitly).
   * @param reuse Reuse any token pointing to the same file.
   */
  protected function create(User.key owner, origin, file, raw, access, dir, bool hidden, File.encryption encryption, bool reuse) {
    if (reuse) {
      query = {location: {everywhere}, teams: true, query: {active: raw.id}}
      match (find(owner, query)) {
        case {some: token}: token
        default: make(owner, origin, file, raw, access, dir, hidden, encryption) |> insert
      }
    } else make(owner, origin, file, raw, access, dir, hidden, encryption) |> insert
  }


  /** {1} Getters. */

  function get(FileToken.id id) { DbUtils.option(/webmail/filetokens[id == id and deleted == none]) }
  function get_active(FileToken.id id) { DbUtils.option(/webmail/filetokens[id == id and deleted == none]/active) }
  function get_owner(FileToken.id id) { DbUtils.option(/webmail/filetokens[id == id and deleted == none]/owner) }
  function getFile(FileToken.id id) { DbUtils.option(/webmail/filetokens[id == id and deleted == none]/file) }
  function get_security(FileToken.id id) { DbUtils.option(/webmail/filetokens[id == id and deleted == none]/security) }
  function get_dir(FileToken.id id) { DbUtils.option(/webmail/filetokens[id == id and deleted == none]/dir) |> Option.bind(identity, _) }
  function get_access(FileToken.id id) { ?/webmail/filetokens[id == id]/access ? {read} }
  function get_link(FileToken.id id) { DbUtils.option(/webmail/filetokens[id == id and deleted == none]/link) |> Option.bind(identity, _) }
  function get_name(FileToken.id id) { DbUtils.option(/webmail/filetokens[id == id and deleted == none]/name/fullname) }
  function get_path(FileToken.id id) { Option.map(Directory.get_path(_, true), get_dir(id)) ? [] }
  function exists(FileToken.id id) { DbUtils.option(/webmail/filetokens[id == id and deleted == none]) |> Option.is_some }
  function hidden(FileToken.id id) { DbUtils.option(/webmail/filetokens[id == id and deleted == none]/hidden) ? false }

  /** Return the encryption parameters. */
  function encryption(FileToken.id id) {
    match (?/webmail/filetokens[id == id].{encryption, active}) {
      case {some: ~{encryption: ~{key, nonce}, active}}:
        filePublicKey = RawFile.publicKey(active)
        ~{nonce, fileSecretKey: key, filePublicKey}
      default: {none}
    }
  }

  /**
   * Return the raw file, file and file token associated with an id.
   * @param active whether to return the active version or the published one.
   */
  function get_all(FileToken.id id, bool active) {
    match (FileToken.get(id)) {
      case {some: token}:
        match (File.get(token.file)) {
          case {some: file}:
            rawid = if (active) token.active else file.published
            match (RawFile.get(rawid)) {
              case {some: raw}: some((token, file, raw))
              default: none
            }
          default:  none
        }
      default: none
    }
  }

  /** Fetch the fields needed to check the user clearance. */
  function get_resource(FileToken.id id) {
    match (DbUtils.option(/webmail/filetokens[id == id and deleted == {none}].{owner, security, access})) {
      case {some: partial}:
        { some:
          { owner: {key: partial.owner, isteam: Team.key_exists(partial.owner)},
            access: partial.access,
            security: some(partial.security),
            src: {file: id} } }
      default: none
    }
  }

  /** Fetch the file's content, as well as name and mimetype. */
  function getContent(FileToken.id id) {
    token = DbUtils.option(/webmail/filetokens[id == id and deleted == none].{active, encryption, name, mimetype})
    match (token) {
      case {some: token}:
        mimetype = token.mimetype
        filename = token.name.fullname
        raw = RawFile.get(token.active)
        content = Option.map(RawFile.getContent, raw) ? {bytes: Binary.create(0)}
        match ((content, token.encryption)) {
          case (~{bytes}, _): ~{content: ~{bytes}, filename, mimetype}
          case (~{filePublicKey, userPublicKey, fileNonce, chunks ...}, ~{key, nonce}):
            content = ~{filePublicKey, userPublicKey, fileNonce, chunks, fileSecretKey: key, tokenNonce: nonce}
            ~{content, filename, mimetype}
          case (_, _):
            warning("getContent: [{id}] encryption mismatch")
            ~{content: {bytes: Binary.create(0)}, filename, mimetype}
        }
      default:
        warning("getContent: [{id}] inexistent token")
        {content: {bytes: Binary.create(0)}, filename: "ERR", mimetype: "text/plain"}
    }
  }

  /** {1} Queries. */

  /**
   * Retrieve tokens which active versions are in the provided list.
   * The sole application is the retrieval of fiel search results.
   */
  function search(User.key owner, list(RawFile.id) rawids) {
    teams = User.get_teams(owner)
    readable = Label.Sem.readable_labels(owner)
    DbSet.iterator(/webmail/filetokens[owner in [owner|teams] and security in readable and hidden == false and deleted == none and active in rawids].{id, active})
  }

  /**
   * Send a search query.
   * Implemented queries are:
   *  - version: find a token based on its active version.
   *  - name: find a token with its name matching the query.
   *  - file: find a token pointing to a file.
   * See the type of queries _ {FileToken.query} _ for more information.
   * @return a maximum of one result matching the query.
   */
  function find(User.key owner, query) {
    teams = if (query.teams) User.get_teams(owner) else []
    match ((query.location, query.query)) {
      case (~{dir}, ~{name}): DbUtils.option(/webmail/filetokens[owner in [owner|teams] and dir == dir and deleted == none and name.fullname == name])
      case (~{dir}, ~{file}): DbUtils.option(/webmail/filetokens[owner in [owner|teams] and dir == dir and deleted == none and file == file])
      case (~{dir}, ~{active}): DbUtils.option(/webmail/filetokens[owner in [owner|teams] and dir == dir and deleted == none and active == active])
      case ({everywhere}, ~{name}): DbUtils.option(/webmail/filetokens[owner in [owner|teams] and deleted == none and name.fullname == name])
      case ({everywhere}, ~{file}): DbUtils.option(/webmail/filetokens[owner in [owner|teams] and deleted == none and file == file])
      case ({everywhere}, ~{active}): DbUtils.option(/webmail/filetokens[owner in [owner|teams] and deleted == none and active == active])
    }
  }

  /**
   * Try finding a secret key and nonce attached to a token pointing to
   * the given raw file. The encryption defaults to {none}.
   */
  function findEncryption(RawFile.id id, User.key user) {
    DbUtils.option(/webmail/filetokens[active == id and owner == user]/encryption) ? {none}
  }

  /**
   * Fetch a total of [chunk] tokens from the database matching the given filter, and all of name greater than the given limit.
   * @param owners: a list of accepted fiel owners. Since user must be able to access team folders as well, user teams
   *  should be passed through this parameters.
   * @return the list of such tokens, ordered by increasing name.
   */
  protected function fetch(list(User.key) owners, string last, int chunk, FileToken.filter filter, list(File.id) exclude) {
    if (filter.name == "")
      DbSet.iterator(/webmail/filetokens[
        owner in owners and name.fullname > last and
        not(file in exclude); limit chunk; order +name.fullname
      ])
    else
      DbSet.iterator(/webmail/filetokens[
        owner in owners and name.fullname > last and
        name.fullname =~ filter.name and not(file in exclude); limit chunk; order +name.fullname
      ])
  }

  /**
   * Return the list of user readable files from the given directory. The conditions which define
   * the readabiliity of a file are:
   *   - clearance to read file (security label).
   *   - user, or one of his teams, is owner of the token.
   *   - token has not been deleted.
   *
   * @param owner owner of the resource.
   * @param select indicates what files to return when at the root directory.
   * @param check activate clearance check.
   * @return the list of such files, ordered by name.
   */
  protected function list(User.key owner, option(Directory.id) dir, select, bool check) {
    owners = match (select) {
      case {teams}: User.get_teams(owner)
      case {user}: [owner]
      case {all}: [owner | User.get_teams(owner)]
    }
    if (check) {
      readable = Label.Sem.readable_labels(owner)
      DbSet.iterator(/webmail/filetokens[
        owner in owners and security in readable and
        dir == dir and deleted == none; order +name.fullname
      ]) |> Iter.to_list
    } else
      DbSet.iterator(/webmail/filetokens[
        owner in owners and dir == dir and deleted == none; order +name.fullname
      ]) |> Iter.to_list
  }

  /** {1} Modifiers. */

  /**
   * Simple setters. All return true iff the operation was successful.
   * {set_labels} and {move} cause the edited field to be upated in the token, while the others are transparent.
   */
  function set_labels(FileToken.id id, Label.labels labels) { @catch(Utils.const(false), { /webmail/filetokens[id == id] <- ~{labels, edited: Date.now()}; true }) }
  function set_link(FileToken.id id, option(Share.link) link) { @catch(Utils.const(false), { /webmail/filetokens[id == id] <- ~{link}; true }) }
  function hide(FileToken.id id, bool hidden) { @catch(Utils.const(false), { /webmail/filetokens[id == id] <- ~{hidden}; true }) }

  /** Move a file token. The ownership of the token changes to that of the destination directory. */
  function move(FileToken.id id, option(Directory.id) dir) {
    @catch(Utils.const(false), {
      owner = Option.bind(Directory.get_owner, dir)
      match (owner) {
        case {some: owner}: /webmail/filetokens[id == id] <- ~{dir, owner, edited: Date.now()}
        default: /webmail/filetokens[id == id] <- ~{dir, edited: Date.now()}
      }
      true
    })
  }

  /**
   * File renaming. No new version is produced. Instead, the published version is renamed
   * and changes are propagated to sibling tokens.
   */
  function rename(FileToken.id id, string newname) {
    log("rename: id={id} newname={newname}")
    match (getFile(id)) {
      case {some: file}:
        File.rename(file, newname)
        ?/webmail/filetokens[id == id]/name/fullname ? newname
      default: newname
    }
  }

  /**
   * Set the security label of a file. Both the file and the filetoken are modified,
   * and modifications are propagated to sibling tokens (this is ensured by the function {File.setClass}).
   *
   * @return true iff the operation was succesful.
   */
  function set_security(FileToken.id id, Label.id security) {
    match (getFile(id)) {
      case {some: file}: File.setClass(file, security) // Propagates the modification to sibling tokens, including the present one.
      default: false
    }
  }

  /**
   * Set the encryption parameters (both raw file and associated tokens), and encrypt
   * the file's secret key for each sharee.
   */
  function encrypt(FileToken.id tid, RawFile.id rid, chunks, encryption, secretKey) {
    // Update the raw file (chunks and encryption).
    chunks = List.map(function (chunk) {
      {chunk with sha: Binary.of_base64(chunk.sha)}
    }, chunks)
    RawFile.encrypt(rid, chunks, encryption)
    // Update the tokens encryption (for each sharee).
    tokens = RawFile.tokens(rid)
    secretKey = Uint8Array.decodeBase64(secretKey)
    Iter.iter(function (token) {
      owner = token.owner
      log("encrypt: generating key for user {owner}")
      // Disambiguation between user and team publicKeys is performed
      // by the function User.publicKey.
      publicKey = Uint8Array.decodeBase64(User.publicKey(owner))
      nonce = TweetNacl.randomBytes(TweetNacl.Box.nonceLength)
      log("encrypt: userPublicKey={Uint8Array.encodeBase64(publicKey)}")
      secretKey = TweetNacl.Box.box(secretKey, nonce, publicKey, secretKey)
      log("encrypt: encryptedSecretKey={Uint8Array.encodeBase64(secretKey)}")
      encryption = {
        key: Uint8Array.encodeBase64(secretKey),
        nonce: Uint8Array.encodeBase64(nonce)
      }
      // Update the token's encryption.
      /webmail/filetokens[id == token.id] <- ~{encryption; ifexists}
    }, tokens)
    // Success !
    {success}
  }

  /** Upload new encryption parameters. */
  function reencrypt(FileToken.id id, File.encryption encryption) {
    /webmail/filetokens[id == id] <- ~{encryption; ifexists}
  }

  /**
   * Update the active version of a token, as well as the raw metdata.
   * NB: no db update if proposed version is the same as the current one.
   * @param token up-to-date token.
   * @param raw new version.
   * @return true if the update was successful.
   */
  function update(FileToken.t token, raw) {
    if (token.active == raw.id && token.name.fullname == raw.name) true
    else
      @catch(Utils.const(false), {
        filename = filename({some: token.id}, token.owner, raw.name, token.dir)
        /webmail/filetokens[id == token.id] <- {
          active: raw.id, name: filename, edited: Date.now(), // Update version.
          size: raw.size, mimetype: raw.mimetype, thumbnail: raw.thumbnail // Update metadata.
        }
        true
      })
  }

  /**
   * Deletion is local only (no propagation, meaning only the access token is removed).
   * TODO: discuss the specification concerning this particular point.
   */
  function delete(FileToken.id id) {
    @catch(Utils.const(false), {
      match (get(id)) {
        case {some: token}:
          // PATCH, always the same bug.
          Db.remove(@/webmail/filetokens[id == id]/deleted)
          /webmail/filetokens[id == id]/deleted <- {some: Date.now()}
          journallog(token, {delete})
          true
        default: false
      }
    })
  }

  /**
   * Fold on the clones of a file token, in case of shared directories.
   * @param original token over whose clones to iterate.
   * @param onself the function to call when encountering the given token.
   * @param onclones the function to call for all other clones.
   */
  function propagate(FileToken.id token, onself, onclones) {
    match (FileToken.get(token)) {
      case {some: token}:
        Directory.propagate(
          token.dir,
          function (_dir) { onself(token) },
          function (clones) {
            List.filter_map(function (clone) {
              copy = DbUtils.option(/webmail/filetokens[
                dir == some(clone.id) and owner == clone.owner and
                file == token.file and deleted == none
              ])
              Option.bind(onclones, copy)
            }, clones)
          }
        )
      default: []
    }
  }

  /** {1} Properties. */

  /** Check the origin of the token. */
  protected function is_shared(FileToken.t token) { match (token.origin) { case {shared: _}: true; default: false } }
  protected function is_upload(FileToken.t token) { token.origin == {upload} }
  protected function is_attachment(FileToken.t token) { match (token.origin) { case {email: _}: true; default: false } }

  @expand both function has_link(FileToken.t token) { Option.is_some(token.link) }


  /** {1} Sharing. */

  /**
   * Share a file with a list of users.
   * Each user receives a token giving access to the file with some restrictions.
   * If the access token authorizes writes, a local version is also created
   * (to be able to rename a file without propagation).
   * If the original file is encrypted, the encryption parameters are returned and
   * decrypted client-side.
   *
   * @param sharer owner of the original file.
   * @param src the original token.
   * @param sharees future owners.
   * @param dst the directory to which the shared files will be copied.
   * @param access access rights of the copy.
   */
  function shareWith(sharer, src, sharees, dst, access) {
    log("shareWith: copy {src} for {sharees}")
    match (get(src)) {
      case {some: token}:
        raw = File.getMetadata(token.file) ? metadata(token)
        outcome = List.fold(function (sharee, outcome) {
          match (outcome.status) {
            case ~{failure}: outcome
            case {success}:
              match (Directory.create_from_path(sharee, dst)) {
                case {some: dir}:
                  copy = FileToken.create(sharee, {shared: sharer}, token.file, raw, access, {some: dir}, token.hidden, {none}, true)
                  match ((token.encryption, raw.encryption)) {
                    case (~{key: fileSecretKey, nonce}, {key: filePublicKey ...}):
                      userPublicKey = User.publicKey(sharee)
                      { outcome with
                        copies: [(sharee, copy.id)|outcome.copies],
                        encryptions: [
                         ~{ file: copy.id, nonce, user: sharee,
                            fileSecretKey, filePublicKey, userPublicKey } |
                          outcome.encryptions
                        ] }
                    default: {outcome with copies: [(sharee, copy.id)|outcome.copies]}
                  }
                default:
                  msg = AppText.non_existent_folder(dst)
                  files = String.concat(", ", List.map(_.f1, outcome.copies))
                  msg =
                    if (List.length(outcome.copies) > 0) msg ^ " ({@intl("succeeded for {files}")})"
                    else msg
                  {outcome with status: Utils.failure(msg, {internal_server_error})}
              }
          }
        }, sharees, {status: {success}, copies: [], encryptions: []})
        // Add the copies to the sharelog.
        ShareLog.create(token.file, sharer, outcome.copies)
        match (outcome.status) {
          case {success}: {success: outcome.encryptions}
          // Destroy bad copies ?
          case ~{failure}: ~{failure}
        }
      default: Utils.failure(AppText.missing_file(src), {wrong_address})
    }
  }

}
