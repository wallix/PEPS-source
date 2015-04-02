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

module FileTokenController {


	/** {1} Utils. */

	private function log(msg) { Log.notice("[FileTokenController]", msg) }
	private function warning(msg) { Log.warning("[FileTokenController]", msg) }
	private function error(msg) { Log.error("[FileTokenController]", msg) }

  /** Fetch the file content. */
  exposed function open(FileToken.id id) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) {
      warning("open: not logged in")
      {raw: "data:text/plain;fileName=error,"}
    } else {
      ownership = FSController.ownership(state.key, {lambda})
      clearance = FSController.clearance({read})
      match (FSController.checkAccess({file: id}, ownership, clearance)) {
        case {success: _resource}:
          file = FileToken.getContent(id)
          match (file.content) {
            case ~{bytes}:
              mimetype = file.mimetype
              encoded = Binary.to_base64(bytes)
              filename = Uri.encode_string(file.filename)
              dataUrl = "data:{mimetype};fileName={filename};base64,{encoded}"
              {raw: dataUrl}
            case ~{filePublicKey, userPublicKey, fileNonce, chunks, fileSecretKey, tokenNonce}:
               ~{ filePublicKey, userPublicKey, fileNonce,
                  chunks, fileSecretKey, tokenNonce, user: state.key,
                  filename: file.filename, mimetype: file.mimetype }
          }
        default:
          warning("open: [{id}] bad ownership / clearance")
          {raw: "data:text/plain;fileName=error,"}
      }
    }
  }

	/**
	 * {1} File operations.
   *
   * Layer-on of the FileToken module. All operations are checked and, if the parent directory is shared,
   * propagated to the owners.
   */

  protected function new(User.key owner, origin, file, raw, access, dir) {
    Directory.propagate(
      dir,
      function (_dir) { void },
      function (clones) {
        log("new: sharing file {file} with clones of directory {dir}")
        // Create a shared version, with the access rights of the parent directory. The origin is: shared.
        // The parameter [reuse] is purposely set to false since we want to have identical folder configurations.
        copies = List.map(function (clone) {
          shared = FileToken.create(clone.owner, {shared: owner}, file, raw, clone.access, {some: clone.id}, false, {none}, false)
          (clone.owner, shared.id)
        }, clones)
        if (copies != []) ShareLog.create(file, owner, copies)
        // New files are never encrypted, so no encryption
        // needed here.
        []
      }
    ) |> ignore
    FileToken.create(owner, origin, file, raw, access, dir, false, {none}, false)
  }

  /**
   * Move a file token locally.
   * If shared directories are involved, must be done:
   *   - if the parent is shared, delete shared copies of the token.
   *   - if the destination is shared, create shared copies.
   */
  protected function move(FileToken.id tid, option(Directory.id) dir) {
    match (FileToken.get(tid)) {
      case {some: token}:
        // Delete shared copies.
        _removed = FileToken.propagate(
          token.id,
          function (_token) { void },
          function (copy) {
            log("move: delete shared copy {copy.id} of {token.id} [{copy.owner}]")
            FileToken.delete(copy.id) |> ignore
            some(copy.id)
          }
        )
        // Create new copies.
        encrypted = Directory.propagate(
          dir,
          function (_dir) { void },
          function (clones) {
            log("move: share file {token.file} with clones of directory {dir}")
            // Access metadata and encryption of the raw file.
            match (RawFile.getMetadata(token.active)) {
              case {some: raw}:
                (copies, encrypted) = match ((token.encryption, raw.encryption)) {
                  case ({key: fileSecretKey, ~nonce}, {key: filePublicKey ...}):
                    List.fold(function (clone, (copies, encrypted)) {
                      // Create a shared version, with the access rights of the parent directory. The origin is: shared.
                      // The parameter [reuse] is purposely set to false since we want to have identical folder configurations.
                      copy = FileToken.create(clone.owner, {shared: token.owner}, token.file, raw, clone.access, {some: clone.id}, false, {none}, false)
                      ( [(clone.owner, copy.id)|copies],
                        [~{ file: copy.id, user: clone.owner, fileSecretKey, filePublicKey, nonce, userPublicKey: User.publicKey(clone.owner) } | encrypted] )
                    }, clones, ([], []))
                  default:
                    copies = List.map(function (clone) {
                      // Create a shared version, with the access rights of the parent directory. The origin is: shared.
                      // The parameter [reuse] is purposely set to false since we want to have identical folder configurations.
                      copy = FileToken.create(clone.owner, {shared: token.owner}, token.file, raw, clone.access, {some: clone.id}, false, {none}, false)
                      (clone.owner, copy.id)
                    }, clones)
                    (copies, [])
                }
                ShareLog.create(token.file, token.owner, copies)
                encrypted
              default: []
            }
          }
        )
        FileToken.move(tid, dir) |> ignore
        encrypted
      default: []
    }
  }

  /**
   * Several things to implement:
   *  - if the parent directory is shared, propagate to owners.
   *  - else normal behaviour
   */
  protected function delete(FileToken.id tid) {
    match (FileToken.get(tid)) {
      case {some: token}:
        parent = token.dir
        FileToken.propagate(
          token.id,
          function (_token) { void },
          function (copy) {
            log("delete: delete shared copy {copy.id} of {token.id} [copy.owner]")
            FileToken.delete(copy.id) |> ignore
            some(copy.id)
          }
        ) |> ignore
      default: void
    }
    FileToken.delete(tid) |> ignore
  }

  /**
   * Get the file content. If the underlaying raw file is encrypted, returns
   * the list of chunks, else nothing.
   */
  protected function getChunks(Login.state state, FileToken.id tid) {
    match (FileToken.get(tid)) {
      case {some: token}:
        if (token.encryption == {none})
          {chunks: Option.map(RawFile.getChunks, RawFile.get(token.active)) ? [], key: state.key, raw: token.active}
        else {encrypted: void}
      default: {missing}
    }
  }

  /**
   * Finish the encryption of a file.
   * The chunks are encrypted client-side, and inserted in the database.
   * This method is also responsible for encrypting the file secret key
   * for each sharee.
   *
   * The active user must own a file token wich admin access to be able
   * to perform this operation.
   */
  exposed function encrypt(FileToken.id tid, RawFile.id rid, chunks, encryption, secretKey) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      Utils.failure(AppText.login_please(), {unauthorized})
    else {
      ownership = FSController.ownership(state.key, {admin})
      clearance = FSController.clearance({admin})
      // Must own (admin ownership) a token with admin access rights.
      match (FSController.checkAccess({file: tid}, ownership, clearance)) {
        case {success: _resource}: FileToken.encrypt(tid, rid, chunks, encryption, secretKey)
        case ~{failure}: ~{failure}
      }
    }
  }

  /** Upload encryption parammeters. */
  exposed function reencrypt(parameters) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      {failure: AppText.login_please()}
    else {
      List.iter(function (parameters) {
        FileToken.reencrypt(parameters.file, parameters.encryption)
      }, parameters)
      {success}
    }
  }

  /**
   * Fetch a fixed amount of file tokens passing the filter.
   * NB: pagesize is only an indication, and the returned number of files may differ depending
   * on the number of files matching the filter.
   *
   * @param last name of the last file of the previous page.
   * @param filter a structured filter expression.
   */
  protected function fetch(User.key owner, string last, int pagesize, FileToken.filter filter, exclude) {
    ref = _.name.fullname
    teams = User.get_teams(owner)
    FileToken.fetch([owner|teams], last, pagesize, filter, exclude) |> Iter.to_list |> Utils.page(_, _.name.fullname, last)
  }

  /** {1} Exposed methods. */

  module Expose {
    @expand function expose(method) {
      state = Login.get_state()
      if (not(Login.is_logged(state))) Utils.Failure.login()
      else method(state)
    }

    // exposed function publish(FileToken.id tid) { expose(FileTokenController.publish(_, tid)) }
    // exposed function sync(FileToken.id tid) { expose(FileTokenController.sync(_, tid)) }
    exposed function getChunks(FileToken.id tid) { expose(FileTokenController.getChunks(_, tid)) }
  } // END EXPOSE

  /** {1} Asynchronous functions. */

  module Async {
    // @async @expand function publish(tid, ('a -> void) callback) { FileTokenController.Expose.publish(tid) |> callback }
    // @async @expand function sync(tid, ('a -> void) callback) { FileTokenController.Expose.sync(tid) |> callback }
    @async @expand function reencrypt(parameters, ('a -> void) callback) { FileTokenController.reencrypt(parameters) |> callback }
    @async @expand function open(id, ('a -> void) callback) { FileTokenController.open(id) |> callback }
    @async @expand function getChunks(id, ('a -> void) callback) { FileTokenController.Expose.getChunks(id) |> callback }
  }

  /** {1} Api functions. */

  module Api {

    /**
     * Upload a file to the given path.
     * @param overwrite if true, the file will be upload as a new file version (if the file already is pre-existant).
     */
    function upload(binary data, string mimetype, Label.id class, Path.t path, bool overwrite) {
      match (List.rev(path)) {
        case [filename|path]:
          state = Login.get_state()
          if (not(Login.is_logged(state))) Utils.Failure.login()
          else {
            path = List.rev(path)
            dir = Directory.create_from_path(state.key, path)
            query = {query: {name: filename}, location: ~{dir}, teams: false}
            match (FileToken.find(state.key, query)) {
              case {some: token}:
                if (overwrite) {
                  File.modify(token.file, data, mimetype, filename, state.key) |> ignore
                  {success: token}
                } else
                  Utils.failure("A file already exists at this path", {forbidden})
              default:
                file = File.create(state.key, filename, mimetype, data, class)
                token = FileToken.create(state.key, {upload}, file.file.id, file.raw, {admin}, dir, false, {none}, false)
                {success: token}
            }
          }
        default: Utils.failure("Empty path", {bad_request})
      }
    }

    /**
     * Build the metadata associated with a file.
     * FIXME: the hash field must be set to the hash of all metadata fields.
     */
    function outcome((FS.metadata, RawFile.t), 'a) metadata(User.key user, FileToken.id tid, bool active) {
      match (FileToken.get_all(tid, active)) {
        case {some: (token, file, raw)}:
          writeAccess = token.owner == user || User.is_in_team(user, token.owner)
          if (not(writeAccess))
            Utils.failure("No access right", {forbidden})
          else if (not(Label.KeySem.user_can_read_security(user, file.security)))
            Utils.failure("Insufficient clearance", {forbidden})
          else
            { success: ({
                id: File.sofid(file.id),
                size: Utils.print_size(raw.size), bytes: raw.size,
                hash: Binary.create(0), thumb_exists: false,
                rev: raw.id, modified: "{raw.created}",
                name: token.name.fullname, path: Path.to_string(FileToken.get_path(token.id)),
                mime_type: raw.mimetype, is_dir: false,
                class: file.security, // New in webmail; file security class.
                icon: "page"
              }, raw) }
        default: Utils.failure("The file was not found at the specified path", {wrong_address})
      }
    }

  } // END API

}
