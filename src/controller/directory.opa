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

module DirectoryController {

	/** {1} Utils. */

	private function log(msg) { Log.notice("DirectoryController: ", msg) }
	private function warning(msg) { Log.warning("DirectoryController: ", msg) }
	private function error(msg) { Log.error("DirectoryController: ", msg) }

	/** {1} Layer-on of the model functions. */

  /**
   * Create a new directory identified by its name and parent. If the parent directory
   * is shared, then clones are created for each of the owners.
   */
  protected function create(Login.state state, option(Directory.id) parent, string name) {
    log("create: name={name} parent={parent}")
    if (name == "")             Utils.failure(AppText.no_folder_name(), {bad_request})
    else
      match (parent) {
        case {some: dir}:
          ownership = FSController.ownership(state.key, {admin})
          clearance = FSController.clearance({write})
          match (FSController.checkAccess(~{dir}, ownership, clearance)) {
            case {success: resource}:
              owner = resource.owner.key
              newdir = Directory.create(owner, name, parent)
              // Note: the created directories inherit the access rights of the parent.
              Directory.propagate(
                parent,
                function (dir) {
                  log("Clone directory '{name}' for original owner '{dir.owner}' with access {dir.access}")
                  Directory.set_clone(newdir.id, {dir: newdir.id, access: dir.access}) |> ignore
                },
                function (clones) {
                  List.iter(function (clone) {
                    log("Clone directory '{name}' for user '{clone.owner}' with access {clone.access}")
                    Directory.clone(clone.owner, name, {some: clone.id}, {dir: newdir.id, access: clone.access}) |> ignore
                  }, clones)
                  []
                }) |> ignore
              {success}

            case ~{failure}: ~{failure}
          }
        // If parent is {none}, we do not need to perform so many checks
        // since by default it represents the root of the FS of the active user.
        // In particular, it cannot be cloned.
        default:
          _newdir = Directory.create(state.key, name, none)
          {success}
      }
  }

  /**
   * If the directory's parent is shared, the renaming operation is propagated to all clone
   * directories. Else, only the local version is renamed.
   */
  function rename(dir, newname) {
    Directory.rename(dir, newname) |> ignore
    parent = Directory.get_parent(dir)
    if (Option.map(Directory.is_shared, parent) ? false) {
      Directory.propagate(
        {some: dir},
        function (_dir) { void },
        function (clones) {
          ids = List.map(_.id, clones)
          Directory.renameAll(ids, newname) |> ignore
          []
        }
      ) |> ignore
    }
  }

  /**
   * Move a directory.
   * Authorized moves are:
   *  - the parent of the moved directory is not shared
   *  - if the parent is shared, the directory can only be moved to the sub directories
   */
  function move(Directory.id id, option(Directory.id) newdir) {
    Directory.move(id, newdir) |> ignore
    match (Directory.get(id)) {
      case {some: origin}:
        Directory.propagate(
          newdir,
          function (dir) {
            log("Clone directory '{origin.name}' for original owner '{origin.owner}' with access {dir.access}")
            Directory.set_clone(origin.id, {dir: origin.id, access: dir.access}) |> ignore
          },
          function (clones) {
            // Share the content with newly created directories.
            copies = List.filter_map(function (parent) {
              log("move: share the content of '{origin.name}' with user '{parent.owner}' with access {parent.access}")
              access = parent.access
              clone = match (origin.clone) {
                case {some: id}: {dir: id, access: FileToken.Access.max(origin.access, access)}
                default: {dir: origin.id, ~access}
              }
              // Search for pre-existing clones.
              match (Directory.findCopy(parent.owner, clone.dir)) {
                // Update the access rights and
                // move the existing clone to the expected place.
                // Also, if the name differ, should rename the directory to the common name.
                case {some: copy}:
                  Directory.set_clone(copy.id, clone) |> ignore
                  Directory.move(copy.id, {some: parent.id}) |> ignore
                  if (copy.name != origin.name) Directory.rename(copy.id, origin.name) |> ignore
                  none
                // Clone the directory.
                default:
                  copy = Directory.clone(parent.owner, origin.name, {some: parent.id}, clone)
                  some((copy.owner, copy.id))
              }
            }, clones)
            // Actually share the content.
            // The resul is the list modifications needed to adapt
            // the file encryptions.
            Directory.shareContent(origin.owner, origin.id, copies, origin.access)
          }
        )
      default: []
    }
  }

  /**
   * Several things to implement:
   *  - if the given directory is the root (its parent is not shared), then only the local version is deleted.
   *  - else if the directory is shared, propagate to owners.
   *  - else normal behaviour
   */
  function delete(User.key owner, Directory.id id) {
    parent = Directory.get_parent(id)
    if (Option.map(Directory.is_shared, parent) ? false)
      Directory.propagate(
        {some: id},
        function (_dir) { void },
        function (clones) {
          log("delete: deleting clone directories of directory '{id}'")
          ids = List.map(_.id, clones)
          Directory.deleteAll(ids)
          []
        }
      ) |> ignore
    Directory.delete(owner, id)
  }

  /** {1} Exposed Methods. */

  module Expose {
    private @expand function publish(method) {
      state = Login.get_state()
      if (not(Login.is_logged(state))) Utils.failure(AppText.login_please(), {unauthorized})
      else method(state)
    }

    exposed function create(option(Directory.id) parent, string name) { publish(DirectoryController.create(_, parent, name)) }
  }

  /** {1} Asynchronous functions. */

  module Async {
    @async @expand function create(parent, name, ('a -> void) callback) { Expose.create(parent, name) |> callback }
  }

	/** {1} API methods. */

  module Api {
    /**
     * Extract the metadata of a directory.
     * @param content whether to return the directory contents
     */
    function FS.metadata metadata(User.key owner, option(Directory.id) dir, bool content) {
    	contents =
    		if (content) {
	        files =
	          FileToken.list(owner, dir, {user}, true) |>
	          List.filter_map(function (token) {
	            match (FileTokenController.Api.metadata(owner, token.id, true)) {
	              case {success: (metadata, _)}: {some: metadata}
	              default: none
	            }
	          }, _)
	        directories =
	          Directory.list(owner, dir, {user}) |>
	          List.rev_map(function (dir) { metadata(owner, {some: dir.id}, false) }, _)
        	List.rev_append(files, directories)
      	} else []
      match (Option.bind(Directory.get, dir)) {
        case {some: dir}:
        	FS.metadata {
        		id: Directory.sofid(dir.id),
				    modified: "{Date.now()}", is_dir: true,
				    path: Path.to_string(Directory.get_path(dir.id, false)),
				    name: dir.name, contents: contents,
				    icon: "folder" }
        default:
        	{ id: "",
			      modified: "{Date.now()}",
			      path: "/", is_dir: true,
			      name: "", contents: contents,
			      icon: "folder" }
      }
    }

  } // END API

}
