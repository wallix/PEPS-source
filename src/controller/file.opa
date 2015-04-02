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

module FileController {

  private function log(msg) { Log.notice("[FileController]", msg) }
  private function debug(msg) { Log.debug("[FileController]", msg) }
  private function warning(msg) { Log.warning("[FileController]", msg) }

  /** {1} Modifiers. */

  /** Return the history of the modifications of a file. */
  exposed function history(File.id file) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) []
    else if (not(File.canRead(state.key, file))) []
    else File.history(file)
  }

  /** Delete a version from the file's history. The active user must have write access to the file. */
  protected function deleteVersion(Login.state state, File.id file, RawFile.id version) {
    // Check write access.
    if (File.canWrite(state.key, file))
      match (File.deleteVersion(file, version)) {
        case {some: published}: {success: published}
        case {none}: Utils.failure(@intl("Could not delete this version"), {bad_request})
      }
    else Utils.Failure.forbidden()
  }

  /** Revert back to a version of the file's history. */
  protected function publishVersion(Login.state state, File.id file, RawFile.id version) {
    // Check write access.
    if (File.canWrite(state.key, file))
      if (File.publishVersion(file, version)) {success: void}
      else Utils.failure(@intl("Could not publish this version"), {bad_request})
    else Utils.Failure.forbidden()
  }

  /** {1} Uploads. */

  /**
   * Check whether a raw file has been corrupted during the transfer.
   * @param self active user, from Login.get_state
   * @param transform function called to transform the data if the file has not been corrupted.
   */
  protected function checkIntegrity(User.key self, RawFile.id id, transform) {
    match (RawFile.get(id)) {
      case {some: raw}:
        if (raw.owner != self) Utils.Failure.forbidden()
        else if (List.length(raw.chunks) < raw.totalchunks) Utils.failure(AppText.unauthorized(), {internal_server_error})
        else transform(raw)
      default: Utils.Failure.notfound()
    }
  }

  /**
   * Upload a new file version. This function is otherwise the same as {file_of_raw}.
   * The raw file is checked for, and once we are sure it has not been corrupted, the
   * file is created in the database. Write access is checked before finishing the upload,
   * the request will have the status 'forbidden' if this check fails.
   */
  exposed function revise(File.id file, RawFile.id version) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) Utils.Failure.login()
    else if (not(File.canWrite(state.key, file))) Utils.Failure.forbidden()
    else
      checkIntegrity(state.key, version, function (RawFile.t raw) {
        version = File.revise(file, raw) // Push the new version.
        RawFile.finish(raw.id, file, version, none) |> ignore // Finalize the raw update.
        {success: file}
      })
  }

  /** Create a new file from a raw file. */
  exposed function register(RawFile.id id) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) Utils.Failure.login()
    else
      checkIntegrity(state.key, id, function (RawFile.t raw) {
        file = File.import(raw, Label.open.id) // Create file. NB: internal label will be overidden by security label selected in upload modal.
        RawFile.finish(raw.id, file.id, 1, none) |> ignore // Update raw.
        {success: file.id}
      })
  }

  /** Layer on the model's purge function. */
  exposed function purge(RawFile.id id) {
    state = Login.get_state()
    if (not(Login.is_logged(state))) Utils.Failure.login()
    else
      match (RawFile.getOwner(id)) {
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
  exposed function void upload(files, File.location where, string security, callback) {
    /**
     * If the file added is shared, try finding the original in the db
     * (to avoid token duplication).
     */
    function find_duplicate(key, file, origin) {
      match (origin) {
        case {upload: _}: none
        default: FileToken.find(key, {teams: true, location: {everywhere}, query: {active: file}})
      }
    }

    state = Login.get_state()
    if (not(Login.is_logged(state)))
      callback(Utils.Failure.login())
    else {
      security = Label.find(state.key, security, {class})
      (dir, owner) =
        match (where) {
          case {directory: dir}:
            match (Directory.get_owner(dir)) {
              case {some: owner}: ({some: dir}, owner)
              default: (none, state.key)
            }
          case ~{path}: (Directory.create_from_path(state.key, path), state.key)
        }
      files = List.map(
        function (upfile) {
          match (File.getRaw(upfile.id)) {
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
                  File.addClass(token.file, security.id) |> ignore
                default: void
              }
              token.file
            default: upfile.id
          }
        }, files)
      callback({success: (dir, files)})
    }
  }

  /** {1} Downloads. */

	/**
	 * Check whether the user can access the current file. Two conditions must be met:
	 *  - the active user is owner of a valid token for this file, or one of its teams is.
	 *  - the active user has clearance to read the file
	 */
	exposed function get(File.id id) {
		state = Login.get_state()
		owner = File.getOwner(id)

		if (not(Login.is_logged(state))) none
		else if (owner != some(state.key) && FileToken.find(state.key, {teams: true, location: {everywhere}, query: {file: id}}) == none) none
		else
			match (File.get(id)) {
	       case {some: file}:
	         if (not(Label.KeySem.user_can_read_security(state.key, file.security))) none
	         else {some: file}
	       default: none
	     }
	}

	exposed function get_attachment(File.id id) {
		match (get(id)) {
			case {some: file}:
				match (RawFile.get(file.published)) {
					case {some: raw}:
						some(~{id, size: raw.size, mimetype: raw.mimetype, name: raw.name})
					default: none
				}
			default: none
		}
  }

  /**
   * Return the binary content of the given file, after checking user access rights.
   * TODO: encrypted attachments will NOT be decrypted, find a solution.
   * @return a record with fields content, mimetype, name, size.
   */
  protected function getAttachment(Login.state state, Message.id mid, File.id fid) {
    match (Message.get_partial(mid)) {
      case {some: message}:
        if (List.mem(fid, message.files))
          match (File.get(fid)) {
            case {some: file}:
              if (not(Label.KeySem.user_can_read_security(state.key, file.security)))
                Utils.Failure.forbidden()
              else
                match (RawFile.get(file.published)) {
                  case {some: raw}:
                    content = RawFile.getBytes(raw)
                    {success: ~{data: content, size: raw.size, attachmentId: fid}}
                  default: Utils.Failure.notfound()
                }
            default: Utils.Failure.notfound()
          }
        else Utils.failure("Attachment not found", {wrong_address})
      default: Utils.failure("Undefined message", {wrong_address})
    }
  }

  exposed function get_thumbnail(File.id id) {
		match (get(id)) {
			case {some: file}:
				match (RawFile.get_thumbnail(file.published)) {
					case {some: picture}: some((file.published, Utils.dataUrl(picture)))
					default: none
				}
			default: none
		}
  }

  /**
   * Return a file thumbnail. If check is true, the function checks the user access rights.
   * The function never fails (no error codes), but returns an empty image if the file is missing
   * or if the user can't access its contents.
   */
  exposed function downloadThumbnail(string id, bool check) {
    state = Login.get_state()
    id = RawFile.idofs(id)
    picture =
      if (not(Login.is_logged(state))) none
      else
        match (RawFile.getMetadata(id)) {
          case {some: metadata}:
            if (not(check)) RawFile.get_raw_thumbnail(metadata)
            else {
              owner = File.getOwner(metadata.file)
              match (File.getClass(metadata.file)) {
                case {some: security}:
                  if (owner != some(state.key) && not(Label.KeySem.user_can_read_security(state.key, security))) none
                  else RawFile.get_raw_thumbnail(metadata)
                default: none
              }
            }
          default: none
        }

    match (picture) {
      case {some: picture}: Resource.binary(picture.data, picture.mimetype)
      default:
        log("download_resource: undefined or unauthorized raw file {id}")
        Resource.binary(Binary.create(0), "image/png")
    }
  }

  module Expose {
    @expand function publish(method) {
      state = Login.get_state()
      if (not(Login.is_logged(state))) Utils.Failure.login()
      else method(state)
    }

    exposed function getAttachment(Message.id mid, File.id fid) { publish(FileController.getAttachment(_, mid, fid)) }
    exposed function deleteVersion(File.id file, RawFile.id version) { publish(FileController.deleteVersion(_, file, version)) }
    exposed function publishVersion(File.id file, RawFile.id version) { publish(FileController.publishVersion(_, file, version)) }
  } // END EXPOSE

  module Async {
    exposed @async function void deleteVersion(File.id file, RawFile.id version, callback) { FileController.Expose.deleteVersion(file, version) |> callback }
    exposed @async function void publishVersion(File.id file, RawFile.id version, callback) { FileController.Expose.publishVersion(file, version) |> callback }
  } // END ASYNC

}
