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

/** Type of API file metadata. */
type FS.metadata = {
  string id,
  string size, // Human readable.
  int bytes,
  binary hash,
  bool thumb_exists,
  RawFile.id rev,
  string modified, // Formatted date.
  string name,
  string path, // Full path ?
  string mime_type,
  bool is_dir,
  Label.id class, // New in webmail; file security class.
  string icon,
} or {
  string id,
  string modified, // Formatted date.
  string name,
  string path, // Full path ?
  bool is_dir,
  string icon,
  FS.Metadata.contents contents // Only applicable to directories.
}
type FS.Metadata.contents = list(FS.metadata)

/**
 * Type of objects manipulated by the controller, which contain the information necessary to
 * check the correctness of operations.
 */
type FS.resource = {
  FS.owner owner,             // Original owner of the resource.
  File.access access,         // If token, access right to the original file.
  Share.source src,           // Pointer to the resource.
  option(Label.id) security   // Security label of the file (directory has optional label).
}
/** Both user and team owners. */
type FS.owner = {User.key key, bool isteam}


module FSController {

  /** {1} Utils. */

  private function log(msg) { Log.notice("[FSController]", msg) }
  private function debug(msg) { Log.debug("[FSController]", msg) }
  private function error(msg) { Log.error("[FSController]", msg) }

  /**
   * Check ownership rights of a resource.
   * The security label is checked at the same time.
   */
  protected function ownership(User.key user, level)(FS.resource rsc) {
    canread = Option.map(Label.KeySem.user_can_read_security(user, _), rsc.security) ? true
    if (not(canread)) false
    else
      match (level) {
        case {super}: rsc.owner.key == user
        case {admin}: rsc.owner.key == user || (rsc.owner.isteam && User.is_team_admin(user, rsc.owner.key))
        case {lambda}: rsc.owner.key == user || (rsc.owner.isteam && User.is_in_team(user, rsc.owner.key))
      }
  }

  /** Check the access rights of a resource. */
  protected @expand function clearance(File.access access)(FS.resource src) {
    FileToken.Access.imply(src.access, access)
  }

  /**
   * Extract a resource and check access:
   *  - ownership: either owner of the resource, or have delegate access
   *  - clearance: check the access rights (admin , write, read)
   */
  protected function checkAccess(Share.source src, ownership, clearance) {
    match (Share.switch(src, FileToken.get_resource, Directory.get_resource)) {
      case {some: resource}:
        if (not(ownership(resource))) Utils.failure(@i18n("You cannot access this resource"), {forbidden})
        else if (not(clearance(resource))) Utils.failure(@i18n("You do not have the clearance to perform this operation"), {forbidden})
        else {success: resource}
      default:
        Utils.failure(@i18n("The requested resource does not exist"), {wrong_address})
    }
  }

  /**
   * Return the resource referenced by the given URN.
   * Does not perform access checks (except for team folders).
   * @return if successful, a token or directory id.
   */
  protected function get_source(Login.state state, URN.t urn) {
    function get_from_path_safe(owner, parent, path) {
      match (Directory.get_from_path(owner, parent, path)) {
        case {inexistent}: Utils.Failure.notfound()
        case ~{dir}: {success: ~{dir}}
        case ~{file}: {success: ~{file}}
      }
    }

    match (urn.mode) {
      case {files: "team"}:
        match (urn.path) {
          case [id|path]:
            // Check the owner of the directory.
            match (Directory.get_owner(id)) {
              case {some: team}:
                if (User.key_exists(team)) Utils.Failure.forbidden()
                else get_from_path_safe(team, {some: id}, path)
              default: Utils.Failure.notfound()
            }
          default: Utils.Failure.notfound()
        }
      case {files: _}: get_from_path_safe(state.key, none, urn.path)
      default: Utils.Failure.notfound()
    }
  }

  /** Same as {get_source}, but eliminate the root directory. */
  protected function get_share_source(Login.state state, URN.t urn) {
    match (get_source(state, urn)) {
      case {success: {dir: {none}}}: Utils.failure("Root directory", {forbidden})
      case {success: {dir: {some: dir}}}: {success: ~{dir}}
      case {success: ~{file}}: {success: {file: file.id}}
      case ~{failure}: ~{failure}
    }
  }

  exposed function rename(Share.source src, newname) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      Utils.Failure.login()
    else if (newname == "")
      Utils.failure(@i18n("You must enter a non empty name"), {bad_request})
    else
      match (checkAccess(src, ownership(state.key, {admin}), clearance({read}))) {
        case {success: _resource}:
          match (src) {
            case {file: tid}:
              setname = FileToken.rename(tid, newname)
                // Automatic publication and update.
                FileToken.publish(tid)
                Option.map(FileToken.syncall, FileToken.get_file(tid)) |> ignore
              {success: setname}
            case ~{dir}:
              DirectoryController.rename(dir, newname) |> ignore
              {success: newname}
          }
        case ~{failure}: ~{failure}
      }
  }

  protected function shareWith(Login.state state, Share.source src, sharees, access) {
    sharer = state.key
    sharername = User.get_username(sharer) ? sharer
    // Extract the usernames, and seperate non-existent users if any.
    (names, notexist) =
      List.fold(function (sharee, (names, notexist)) {
        match (User.get_username(sharee)) {
          case {some: username}: ([username|names], notexist)
          default: (names, [sharee|notexist])
        }
      }, sharees, ([], []))

    match (notexist) {
      case []:
        // NB: the resource must have access rights higher than the requested ones: {access}.
        match (checkAccess(src, ownership(sharer, {lambda}), clearance(access))) {
          case {success: _resource}:
            match (src) {
              case ~{file}:
                match (FileToken.shareWith(sharer, file, sharees, ["Shared"], access)) {
                  case {success: copies}:
                    name = FileToken.get_name(file)
                    // Send a message alerting sharees of the new file.
                    subject = @i18n("File '{name}'' from {sharername}")
                    content = @i18n("File '{name}' from {sharername} has been added to your 'shared' directory")
                    List.iter(MessageController.send_local_mail(_, subject, content, []), sharees)
                    // Return the copies that need to be approved by the active user.
                    {success: copies}
                  case ~{failure}: ~{failure}
                }
              case ~{dir}:
                match (Directory.shareWith(sharer, dir, sharees, ["Shared"], access)) {
                  case {success: copies}:
                    name = Directory.get_name(dir)
                    // Send a message alerting sharees of the new file.
                    subject = @i18n("Directory '{name}'' from {sharername}")
                    content = @i18n("Directory '{name}' from {sharername} has been added to your 'shared' directory")
                    List.iter(MessageController.send_local_mail(_, subject, content, []), sharees)
                    // Return the copies that need to be approved by the active user.
                    {success: copies}
                  case ~{failure}: ~{failure}
                }
            }
          case ~{failure}: ~{failure}
        }
      default:
        Utils.failure(AppText.missing_user(notexist), {wrong_address})
    }
  }

  exposed function move(Share.source src, option(Directory.id) newdir) {
    state = Login.get_state()
    exists = Option.map(Directory.exists, newdir) ? true
    parent = Share.switch(src, FileToken.get_dir, Directory.get_parent)
    isshared = Option.map(Directory.is_shared, parent) ? false
    isdir = Share.isdir(src)
    if (not(Login.is_logged(state)))
      Utils.Failure.login()
    else if (not(exists))
      Utils.failure(@i18n("Inexistent directory {newdir}"), {wrong_address})
    else if (isshared && isdir)
      Utils.failure(@i18n("This directory is shared and cannot be moved"), {forbidden})
    else
      match (checkAccess(src, ownership(state.key, {admin}), clearance({read}))) {
        case {success: resource}:
          encrypted = Share.switch(src, FileTokenController.move(_, newdir), DirectoryController.move(_, newdir))
          {success: (state, parent, encrypted)}
        case ~{failure}: ~{failure}
      }
  }

  /**
   * Change the given file's security label. Checks to be performed:
   *   - login and ownership
   *   - can use the security label (sufficient clearance)
   *   - can modify the file ({admin} access rights)
   */
  exposed function set_security(Share.source src, Label.id class) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      Utils.Failure.login()
    else if (not(Label.KeySem.user_can_use_label(state.key, class)))
      Utils.failure(@i18n("You are not allowed to use this label"), {forbidden})
    else {
      ownership = ownership(state.key, {admin})
      clearance = clearance({admin})
      match (checkAccess(src, ownership, clearance)) {
        case {success: _resource}:
          dir = Share.switch(src, FileToken.get_dir, Directory.get_parent)
          Share.switch(src, FileToken.set_security(_, class), Directory.set_security(_, some(class))) |> ignore
          {success: dir}
        case ~{failure}: ~{failure}
      }
    }
  }

  /**
   * Filter labels that can not be used by the given user.
   * Since changes are local, minimal checks:
   *    - login and ownership
   *    - clearance to use the labels
   *
   * In particular, does not check whether the user can read the file (security label).
   */
  private function invalid_labels(User.key key, list(Label.t) labels) {
    if (labels == [] || User.is_super_admin(key)) []
    else
      match (User.get(key)) {
        case {none}: labels
        case {some: user}:
          List.filter(function (label) { not(Label.Sem.user_can_read_label(user,label)) },labels)
      }
  }
  exposed function set_labels(Share.source src, labels) {
    state = Login.get_state()
    invalid = invalid_labels(state.key, labels)
    if (not(Login.is_logged(state)))
      Utils.Failure.login()
    else if (invalid != [])
      Utils.failure(AppText.invalid_labels(List.map(_.name, invalid)), {bad_request})
    else
      match (checkAccess(src, ownership(state.key, {admin}), clearance({write}))) {
        case {success: _resource}:
          lblids = List.map(_.id, labels)
          Share.switch(src, FileToken.set_labels(_, lblids), Directory.set_labels(_, lblids)) |> ignore
          {success}
        case ~{failure}: ~{failure}
      }
  }

  /**
   * Delete a file token. Again, the changes are local (unless otherwise decided in the specification).
   * the checks are the same as 'set_labels'.
   */
  protected function delete(Login.state state, Share.source src) {
    match (checkAccess(src, ownership(state.key, {admin}), clearance({read}))) {
      case {success: _resource}:
        match (src) {
          case {file: tid}:
            parent = FileToken.get_dir(tid)
            FileTokenController.delete(tid)
            {success: parent}
          case ~{dir}:
            parent = Directory.get_parent(dir)
            DirectoryController.delete(state.key, dir)
            {success: parent}
        }
      case ~{failure}: ~{failure}
    }
  }

  /**
   * Create (and delete) a share link. Not to get mixed up with user sharing (named 'share_with',
   * not really suggestive).
   */
  protected function share(Login.state state, Share.source src) {
    match (checkAccess(src, ownership(state.key, {admin}), clearance({read}))) {
      case {success: _resource}:
        link = Share.create(state.key, src)
        parent = Share.switch(src, FileToken.get_dir, Directory.get_parent)
        {success: (parent, link)}
      case ~{failure}: ~{failure}
    }
  }
  /** Every user with admin rights over the file can edit the share link. */
  protected function unshare(Login.state state, string link) {
    match (Share.get(link)) {
      case {some: share}:
        match (checkAccess(share.src, ownership(state.key, {admin}), clearance({read}))) {
          case {success: _resource}:
            Share.remove(state.key, share) |> ignore
            {success}
          case ~{failure}: ~{failure}
        }
      default:
        Utils.failure(AppText.inexistent_link(), {wrong_address})
    }
  }

  /**
   * {2 Mail files.}
   *
   * Thies two functions are used only once, to confirm the deletion of
   * the raw file behind a mail file.
   * Temporarily cut out, until more precise specification.
   *

  protected function is_file_owner(User.key key, RawFile.id fid) {
    match (RawFile.get_owner(fid)) {
      case { none }: true
      case { some: owner }: owner == key
    }
  }

  protected function do_delete(User.key key, File.id fid) {
    if (is_file_owner(key, fid)) File.delete(fid) else void
  }

  */

  /** {2} Uploads. */

  /** Create a new file from a raw file. */
  exposed function file_of_raw(RawFile.id id) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) Utils.Failure.login()
    else
      match (RawFile.get(id)) {
        case {some: raw}:
          if (raw.owner != state.key) Utils.Failure.forbidden()
          else if (List.length(raw.chunks) < raw.totalchunks) Utils.failure(AppText.unauthorized(), {internal_server_error})
          else {
            file = File.import(raw, Label.open.id) // Create file. NB: internal label will be overidden by security label selected in upload modal.
            RawFile.finish(raw.id, file.id, 1, none) |> ignore // Update raw.
            {success: file.id}
          }
        default: Utils.Failure.notfound()
      }
  }

  /** Layer on the model's purge function. */
  exposed function purge(RawFile.id id) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) Utils.Failure.login()
    else
      match (RawFile.get_owner(id)) {
        case {some: owner}:
          if (owner != state.key) Utils.Failure.forbidden()
          else {
            RawFile.purge(id)
            {success}
          }
        default: Utils.Failure.notfound()
      }
  }

  /**
   * Annoying thing about this function: returns a garbage id
   * when it should fail (id == "please login").
   * FIXME return an outcome instead.
   */
  protected function string upload_file(name, mimetype, binary data) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) AppText.login_please()
    else
      File.create(state.key, name, mimetype, data, Label.attached.id).file.id
      |> File.sofid
  }

  /**
   * If the file added is shared, try finding
   * the original in the db (to avoid duplication).
   */
  private function find_duplicate(key, file, origin) {
    match (origin) {
      case {upload: _}: none
      default: FileToken.find(key, {teams: true, location: {everywhere}, query: {active: file}})
    }
  }

  /**
   * Upload the files attached to a mail to the user's file system.
   * Depending on the origin, the file is either:
   *   - shared: ignored (because the file already present in the FS)
   *   - uploaded: added to the 'attached' directory (because the file has just been imported,
   *      but never added to the FS)
   * @param files list of { origin: File.origin, string name, id: File.id }
   * @param security unparsed security label
   * @param where destination of the upload.
   * @param callback the callback function, expecting a list of fileTokens (encapsulated in an outcome)
   */
  @async
  exposed function void upload(files, either(Directory.id, Path.t) where, string security, callback) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      callback(Utils.Failure.login())
    else {
      security = Label.find(state.key, security, {class})
      (dir, owner) =
        match (where) {
          case {left: dir}:
            match (Directory.get_owner(dir)) {
              case {some: owner}: ({some: dir}, owner)
              default: (none, state.key)
            }
          case {right: path}: (Directory.create_from_path(state.key, path), state.key)
        }
      files = List.map(
        function (upfile) {
          match (File.get_raw(upfile.id)) {
            case {some: raw}:
              // Lookup the version to avoid duplicates.
              // If the origin is [shared], lookup a FileToken whose active version is the
              // given one, else, created a new token.
              duplicate = find_duplicate(owner, raw.id, upfile.origin)
              token = match (duplicate) {
                // File token pre-existant.
                case {some: token}: token
                default:
                  // No file token: create one.
                  token = FileTokenController.new(owner, upfile.origin, upfile.id, raw, {admin}, dir)
                  // Index the raw file in solr.
                  // We have to push this since if solr isn't running we'll lock up the modal.
                  Scheduler.push(function () {
                    Search.File.extract(
                      raw.id, RawFile.getBytes(raw),
                      raw.name, raw.mimetype) |> ignore
                  })
                  // Return the token.
                  token
              }

              match (security) {
                case {some: security}:
                  // Does not override existing security labels, only internal ones.
                  File.add_security(token.file, security.id) |> ignore
                default: void
              }
              token.file
            default: upfile.id
          }
        }, files)
      callback({success: (dir, files)})
    }
  }

  /** Expose controller methods. */
  module Expose {
    @expand function publish(method) {
      state = Login.get_state()
      if (not(Login.is_logged(state))) Utils.Failure.login()
      else method(state)
    }

    exposed function delete(Share.source src) { publish(FSController.delete(_, src)) }
    exposed function shareWith(Share.source src, users, access) { publish(FSController.shareWith(_, src, users, access)) }
    exposed function share(Share.source src) { publish(FSController.share(_, src)) }
    exposed function unshare(string link) { publish(FSController.unshare(_, link)) }
  }

  /** Asynchronous functions. */
  module Async {
    @async @expand function move(src, newdir, ('a -> void) callback) { FSController.move(src, newdir) |> callback }
    @async @expand function rename(src, newname, ('a -> void) callback) { FSController.rename(src, newname) |> callback }
    @async @expand function shareWith(src, keys, access, ('a -> void) callback) { FSController.Expose.shareWith(src, keys, access) |> callback }
    @async @expand function delete(src, ('a -> void) callback) { FSController.Expose.delete(src) |> callback }
    @async @expand function share(src, ('a -> void) callback) { FSController.Expose.share(src) |> callback }
    @async @expand function unshare(link, ('a -> void) callback) { FSController.Expose.unshare(link) |> callback }
    @async @expand function set_security(src, class, ('a -> void) callback) { FSController.set_security(src, class) |> callback }
  } // END ASYNC

  /** API reserved functions. */
  module Api {
    /**
     * Download and format a file or directory into a form suitable for API
     * download. The directory is only return if {content} is set to false.
     * @param src the source file or directory
     * @param content include the file content
     * @param active return the active or published version
     */
    protected function download(User.key owner, src, bool content, bool active) {
      match (src) {
        case ~{dir}:
          metadata = DirectoryController.Api.metadata(owner, dir, content)
          content = Binary.create(0)
          {success: (content, "directory", "", metadata)}
        case ~{file}:
          match (FileTokenController.Api.metadata(owner, file.id, active)) {
            case {success: (metadata, raw)}:
              content = if (content) RawFile.getBytes(raw) else Binary.create(0)
              {success: (content, raw.mimetype, raw.name, metadata)}
            case ~{failure}: ~{failure}
          }
      }
    }

    /** Specifically extract the file metadata. */
    @expand protected function metadata(User.key owner, src, bool content, bool active) {
      match (download(owner, src, content, active)) {
        case {success: (_, _, _, metadata)}: {success: metadata}
        case ~{failure}: ~{failure}
      }
    }

    /** Same as non-API, with the identification of the source and destination directories interposed. */
    protected function move(string root, Path.t src, Path.t dst, bool copy) {
      state = Login.get_state()
      // Find the destination file/folder.
      match (List.rev(dst)) {
        case [newname|path]:
          path = List.rev(path)
          dst = get_source(state, {mode: {files: root}, ~path}) // Directories not auto-created.
          src = get_share_source(state, {mode: {files: root}, path: src})
          match ((src, dst)) {
            case ({success: src}, {success: ~{dir}}):
              match (FSController.move(src, dir)) {
                case {success: _}: {success}
                case ~{failure}: ~{failure}
              }
            case ({failure: _}, _): Utils.failure("The source file was not found at the specified path", {wrong_address})
            case (_, {success: {file: _}}): Utils.failure("The destination path points to a file: {path}", {forbidden})
            default: Utils.failure("Non existent destination directory: {path}", {wrong_address})
          }
        default:
          Utils.failure("The destination path cannot be the root directory", {forbidden})
      }
    }

    /** Same as non-API, with the identification of the source and destination directories interposed. */
    protected function delete(string root, Path.t path) {
      state = Login.get_state()
      src = get_share_source(state, {mode: {files: root}, ~path})
      match (src) {
        case {success: src}:
          match (FSController.delete(state, src)) {
            case {success: _}: {success}
            case ~{failure}: ~{failure}
          }
        default: Utils.failure("The source file was not found at the specified path", {wrong_address})
      }
    }

  } // END API

}
