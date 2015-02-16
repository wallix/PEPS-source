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

	/**
	 * Check whether the user can access the current file. Two conditions
	 * must be met:
	 *  - the active user is owner of a valid token for this file, or one of its teams is.
	 *  - the active user has clearance to read the file
	 */
	exposed function get(File.id id) {
		state = Login.get_state()
		owner = File.get_owner(id)

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
   * Return the binary content of the given file, after
   * checking user access rights.
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
   * Check whether the user can access this current thumbnail. Knowing that thumbnails must be accessible to other users,
   * the conditions for reading it are more lenient:
   *  - the active user has clearance to read the file
   */
  protected function get_raw_thumbnail(Login.state state, RawFile.id id) {
    match (RawFile.get_file(id)) {
      case {some: file}:
        owner = File.get_owner(file)
        match (File.get_security(file)) {
          case {some: security}:
            if (owner != some(state.key) && not(Label.KeySem.user_can_read_security(state.key, security))) none
            else RawFile.get_thumbnail(id)
          default: none
        }
      default: none
    }
  }

  protected function download_thumbnail(string id) {
    state = Login.get_state()
    if (not(Login.is_logged(state)))
      Resource.binary(Binary.create(0), "image/png")
    else
      match (get_raw_thumbnail(state, RawFile.idofs(id))) {
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
  } // END EXPOSE

}
